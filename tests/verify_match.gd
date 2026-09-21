extends Node2D
## Regression suite for the 3v3 match loop: spawns, countdown, clock, survivors,
## overtime, win/lose/draw, spectating and rematch.
##
## Run (must run as a scene - AGENTS.md pitfall 12):
##   godot --path . --fixed-fps 60 res://tests/verify_match.tscn
##   godot --headless --path . --fixed-fps 60 res://tests/verify_match.tscn
## Exit code 0 = every check passed.
##
## Damage is applied through the real effect the skills carry, so the chain
## gameplay -> vital -> bus -> director is exercised, not a mock.

const MAIN_SCENE: String = "res://main/main.tscn"
const BULLET_DAMAGE: String = "res://skills/data/shared/effects/bullet_damage.tres"
const FREEZE_EFFECT: String = "res://skills/data/shared/effects/apply_frozen.tres"
const SECOND: int = 60

var _checks: int = 0
var _failed: int = 0
var _main: Node2D = null
var _director: MatchDirector = null
var _player: Unit = null
var _overlay: ResultOverlay = null
var _damage: GameplayEffect = null

func _ready() -> void:
	get_tree().root.size = Vector2i(1152, 648)
	_damage = load(BULLET_DAMAGE) as GameplayEffect
	await _frames(1)
	_main = (load(MAIN_SCENE) as PackedScene).instantiate() as Node2D
	# Directly under root, so it can be the tree's current scene and so restart()
	# reloads main.tscn instead of this test scene.
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	await _frames(3)
	_bind()
	if _director == null or _player == null:
		print("FAIL | setup: could not bind the arena")
		get_tree().quit(1)
		return
	await _run()
	print("=== match flow: %d/%d checks passed ===" % [_checks - _failed, _checks])
	get_tree().quit(1 if _failed > 0 else 0)

func _bind() -> void:
	_main = get_tree().current_scene as Node2D
	_director = _main.get_node("MatchDirector") as MatchDirector
	_player = _director.human_unit
	_overlay = _main.get_node("HUD/ResultOverlay") as ResultOverlay

func _run() -> void:
	# --- 1. Spawning: three units per side, the local player among them ---------
	_check("both teams spawned three units", _units_of(Teams.Id.BLUE).size() == 3
		and _units_of(Teams.Id.RED).size() == 3,
		"blue=%d red=%d" % [_units_of(Teams.Id.BLUE).size(), _units_of(Teams.Id.RED).size()])
	_check("the local player controls the blue unit named Player",
		_player != null and _player.name == "Player" and _player.team == Teams.Id.BLUE)
	_check("teammates are AI", _first_bot(Teams.Id.BLUE) != null)
	_check("all units start alive and unseparated",
		_director.living(Teams.Id.BLUE) == 3 and _director.living(Teams.Id.RED) == 3,
		"blue=%d red=%d" % [_director.living(Teams.Id.BLUE), _director.living(Teams.Id.RED)])
	_check("the local player is the only human unit",
		_units_with_controller(Unit.Controller.HUMAN).size() == 1)

	# --- 2. READY freezes the world --------------------------------------------
	_check("boots into READY", _director.state == MatchDirector.State.READY,
		"state=%d" % _director.state)
	_check("READY freezes the world", get_tree().paused)
	_check("the clock starts at the full match length", _director.time_text() == "1:00",
		_director.time_text())
	_check("the score starts level", _score_text() == "3 : 3", _score_text())

	# --- 3. PLAYING runs the clock ---------------------------------------------
	await _wait_playing()
	_check("countdown ends in PLAYING", _director.is_playing())
	_check("PLAYING unfreezes the world", not get_tree().paused)
	var before := _director.time_left()
	await _frames(SECOND)
	_check("clock runs down", _director.time_left() < before - 0.9,
		"%.1f -> %.1f" % [before, _director.time_left()])

	# --- 4. The other team fights back -----------------------------------------
	# Put a red unit next to the local player so the fight is deterministic instead
	# of waiting for a bot to walk across the arena.
	var attacker := _units_of(Teams.Id.RED)[0]
	# Walls sit between the spawn rows (cols 6-11 at the top rows), so the duel is
	# moved to the clear middle lane of the arena.
	_player.global_position = Vector2(300.0, 368.0)
	attacker.global_position = _player.global_position + Vector2(220.0, 0.0)
	attacker.set_physics_process(false)	# hold position, keep firing
	# Teammates would walk into the line of fire while chasing; hold them still so
	# this test measures the attacker's aim, not body-blocking.
	for mate in _units_of(Teams.Id.BLUE):
		if mate != _player:
			mate.set_physics_process(false)
	var health_before := _player.health_ratio()
	var hit := await _wait_for(func() -> bool: return _player.health_ratio() < health_before, 10 * SECOND)
	_check("an enemy unit damages the local player", hit, "health=%.2f" % _player.health_ratio())

	# --- 5. Losing the local player does NOT end the match ---------------------
	_hurt(_player, 200.0, attacker)
	await _frames(2)
	_check("the local player is down", not _player.is_alive())
	_check("the match continues while teammates live", _director.is_playing(),
		"state=%d" % _director.state)
	_check("the camera moved to a living teammate",
		_camera_target() != null and _camera_target() != _player and _camera_target().is_alive(),
		"camera on %s" % ["<none>" if _camera_target() == null else _camera_target().name])
	_check("the score shows the loss", _score_text() == "2 : 3", _score_text())

	# --- 6. Wiping a team ends it ---------------------------------------------
	for unit in _units_of(Teams.Id.RED):
		_hurt(unit, 200.0, _player)
	await _frames(2)
	_check("wiping the red team wins the match",
		_director.result == MatchDirector.Result.BLUE_WINS, "result=%d" % _director.result)
	_check("the local player's side is the winner", _director.player_won())
	_check("FINISHED freezes the world again", get_tree().paused)
	_check("result overlay is shown", _overlay.visible)
	_check("overlay reads YOU WIN", _overlay.get_node("Title").text == "YOU WIN",
		_overlay.get_node("Title").text)
	_check("the scoreboard has a row per participant", _overlay_row_count() == 6,
		"rows=%d" % _overlay_row_count())

	# --- 7. Rematch respawns everyone -----------------------------------------
	_director.restart()
	await _frames(4)
	_bind()
	await _frames(2)
	_check("rematch returns to READY", _director.state == MatchDirector.State.READY,
		"state=%d" % _director.state)
	_check("rematch freezes the world", get_tree().paused)
	_check("rematch hides the overlay", not _overlay.visible)
	_check("rematch respawns all six units",
		_director.living(Teams.Id.BLUE) == 3 and _director.living(Teams.Id.RED) == 3,
		"blue=%d red=%d" % [_director.living(Teams.Id.BLUE), _director.living(Teams.Id.RED)])

	# --- 8. Level at the end of the clock -> overtime --------------------------
	await _wait_playing()
	_director.match_seconds = 1.0
	_director.ready_seconds = 0.0
	_director.start()
	await _frames(int(1.5 * SECOND))
	_check("level survivors at 0:00 start overtime",
		_director.is_overtime() and _director.is_playing(),
		"overtime=%s state=%d" % [_director.is_overtime(), _director.state])
	_check("overtime adds its own 30 seconds", _director.time_left() > 29.0,
		"%.1f" % _director.time_left())
	_check("no result yet while overtime is level", _director.result == MatchDirector.Result.NONE,
		"result=%d" % _director.result)
	# First unit to fall in overtime loses the match.
	_hurt(_units_of(Teams.Id.RED)[0], 200.0, _player)
	await _frames(2)
	_check("the first loss in overtime decides it",
		_director.result == MatchDirector.Result.BLUE_WINS, "result=%d" % _director.result)
	_check("the reason names the survivors",
		_director.reason.contains("Overtime"), _director.reason)

	# --- 9. Frost silences a bot caster ---------------------------------------
	_director.restart()
	await _frames(4)
	_bind()
	await _wait_playing()
	var bot := _first_bot(Teams.Id.RED)
	var ai := bot.get_node("AiRouter") as AiAbilityRouter
	_check("bot AI is not silenced by default", not ai.is_silenced())
	(load(FREEZE_EFFECT) as GameplayEffect).apply(bot, _player, {})
	_check("frost silences a bot caster", ai.is_silenced(),
		"frozen=%s" % bot.is_frozen())
	_check("status tags reach the plugin's tag database",
		TagManager.has_tag(bot, &"state.frozen"))

# --- helpers ----------------------------------------------------------------
func _units_of(team: int) -> Array[Unit]:
	var found: Array[Unit] = []
	for node in get_tree().get_nodes_in_group(Teams.group_of(team)):
		var unit := node as Unit
		if unit != null and unit.is_alive():
			found.append(unit)
	return found

func _units_with_controller(controller: Unit.Controller) -> Array[Unit]:
	var found: Array[Unit] = []
	for node in get_tree().get_nodes_in_group(&"units"):
		var unit := node as Unit
		if unit != null and unit.controller == controller:
			found.append(unit)
	return found

func _first_bot(team: int) -> Unit:
	for node in get_tree().get_nodes_in_group(Teams.group_of(team)):
		var unit := node as Unit
		if unit != null and not unit.is_human():
			return unit
	return null

## Unit the camera is watching (it switches to a teammate when the player dies).
func _camera_target() -> Unit:
	var camera := _main.get_node_or_null("Camera") as UnitCamera
	return null if camera == null else camera.follow as Unit

func _score_text() -> String:
	var label := _main.get_node_or_null("HUD/Score") as Label
	return "" if label == null else label.text

func _overlay_row_count() -> int:
	return _overlay._rows.size() if _overlay != null else 0

## Applies the effect the skills carry - the real damage path, not a vital poke.
func _hurt(target: Node, amount: float, instigator: Node) -> void:
	if not is_instance_valid(target):
		return
	for _i in int(ceilf(amount / 10.0)):
		(_damage.duplicate(true) as GameplayEffect).apply(target, instigator, {})

func _wait_playing(max_frames: int = 8 * SECOND) -> bool:
	return await _wait_for(func() -> bool: return _director.is_playing(), max_frames)

func _wait_for(condition: Callable, max_frames: int) -> bool:
	for _i in max_frames:
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()

func _check(label: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	if not passed:
		_failed += 1
	print("%s | %s%s" % ["PASS" if passed else "FAIL", label, "" if detail.is_empty() else "  <- " + detail])

func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame
