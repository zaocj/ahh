extends Node2D
## Regression suite for the aiming-indicator lifecycle.
##
## Why it exists: the ability plugin only frees a preview (and its indicator) when
## the game calls cancel/cancel_targeting() - it never ends a preview on its own
## and it keeps a single `_indicator` reference. So any second begin() without a
## cancel, or any missed cancel, leaves a SkillIndicator drawing on the map
## forever. The game side (SkillButton pointer ownership + AbilityInputRouter
## preview ownership) is what has to guarantee the cancel happens.
##
## Run (must run as a scene - AGENTS.md pitfall 12):
##   godot --path . --fixed-fps 60 res://tests/verify_indicator.tscn     # 17/17
##   godot --headless --path . --fixed-fps 60 res://tests/verify_indicator.tscn
## The headless run skips the two checks that go through Input.parse_input_event
## (headless drops those events on the floor). Exit code 0 = every check passed.

const MAIN_SCENE: String = "res://main/main.tscn"
## Simulated seconds to skip, for ability cooldowns (they tick by delta).
const COOLDOWN_FRAMES: int = 70

var _checks: int = 0
var _failed: int = 0
var _main: Node2D = null
var _router: AbilityInputRouter = null
var _player: Unit = null
var _bullet: SkillButton = null

func _ready() -> void:
	# Headless windows default to 64x64 (AGENTS.md pitfall 8).
	get_tree().root.size = Vector2i(1152, 648)
	_main = (load(MAIN_SCENE) as PackedScene).instantiate() as Node2D
	add_child(_main)
	await _frames(2)
	_router = _main.get_node("Player/InputRouter") as AbilityInputRouter
	_player = _main.get_node("Player") as Unit
	_bullet = _main.get_node("HUD/SkillBullet") as SkillButton
	# main.tscn boots into a match countdown (MatchDirector pauses the tree) and the
	# enemy eventually shoots the player: the checks below need a running world that
	# does not end under them, so silence the enemy AI and use a long clock.
	var director := _main.get_node("MatchDirector") as MatchDirector
	_silence_bots()
	director.match_seconds = 600.0
	director.start()
	for _i in 8 * 60:
		if director.is_playing():
			break
		await get_tree().process_frame
	await _run()
	print("=== indicator lifecycle: %d/%d checks passed ===" % [_checks - _failed, _checks])
	get_tree().quit(1 if _failed > 0 else 0)

func _run() -> void:
	var center := _bullet.get_global_rect().get_center()
	_check("clean start: no indicator", _count() == 0, "got %d" % _count())

	# --- 1. One touch must press once, in either event order -----------------
	# A touch also produces an emulated mouse event
	# (input_devices/pointing/emulate_mouse_from_touch, on by default). Both used
	# to pass the button's "not already pressed" guard, so one finger started the
	# preview twice; the strategy keeps only its newest indicator, so the first
	# stayed on the map for the rest of the match. Which of the two events arrives
	# first is up to the engine, so both orders are checked.
	_bullet._gui_input(_mouse_press(center))
	_bullet._gui_input(_touch_press(center))
	_check("press order mouse->touch: one preview", _count() == 1, "got %d" % _count())
	_bullet._gui_input(_mouse_release(center))
	_bullet._gui_input(_touch_release(center))
	_check("  ... and the release clears the indicator", _count() == 0, "got %d" % _count())
	# The cooldown is committed by the behavior tree during execution, not inside
	# try_activate_ability(), so give it a couple of frames.
	await _frames(3)
	_check("the tap still cast the ability", _router.cooldown_ratio(0) > 0.0,
		"ratio=%f" % _router.cooldown_ratio(0))

	await _frames(COOLDOWN_FRAMES)
	_bullet._gui_input(_touch_press(center))
	_bullet._gui_input(_mouse_press(center))
	_check("press order touch->mouse: one preview", _count() == 1, "got %d" % _count())
	_bullet._gui_input(_touch_release(center))
	_bullet._gui_input(_mouse_release(center))
	_check("  ... and the release clears the indicator", _count() == 0, "got %d" % _count())

	# --- 2. Same thing through the engine's real input path ------------------
	# Input.parse_input_event() buffers: the event only reaches the GUI on the next
	# flush, hence the frame waits. Under --headless these events are dropped.
	await _frames(COOLDOWN_FRAMES)
	if DisplayServer.get_name() == "headless":
		_skip("engine touch press -> one indicator", "headless drops parse_input_event")
		_skip("engine touch release -> no indicator", "headless drops parse_input_event")
	else:
		var press := InputEventScreenTouch.new()
		press.index = 0
		press.position = center
		press.pressed = true
		Input.parse_input_event(press)
		await _frames(2)
		_check("engine touch press -> one indicator", _count() == 1, "got %d" % _count())
		var release := InputEventScreenTouch.new()
		release.index = 0
		release.position = center
		release.pressed = false
		Input.parse_input_event(release)
		await _frames(2)
		_check("engine touch release -> no indicator", _count() == 0, "got %d" % _count())

	# --- 3. Pressing another slot owns the preview ---------------------------
	await _frames(COOLDOWN_FRAMES)
	var at := Vector2.ZERO
	_router.press(0, at)
	_check("press slot 0: one indicator", _count() == 1, "got %d" % _count())
	_router.press(1, at)
	_check("press slot 1: the slot 0 indicator is gone", _count() == 1, "got %d" % _count())
	# The finger that owned slot 0 can release late; it must not decide anything.
	_router.release(0, at)
	_check("stale release of slot 0 leaves slot 1 aiming", _count() == 1, "got %d" % _count())
	_router.release(1, at)
	_check("release slot 1: no indicator", _count() == 0, "got %d" % _count())

	# --- 4. A second begin() without cancel must not orphan the first --------
	await _frames(COOLDOWN_FRAMES + 60)
	_router.press(0, at)
	_router.ability_instance(0).start_targeting()
	_check("re-begin without cancel keeps exactly one indicator", _count() == 1, "got %d" % _count())
	_router.cancel_aim()
	_check("cancel_aim clears the indicator", _count() == 0, "got %d" % _count())

	# --- 5. A preview nobody owns is released by the router watchdog ---------
	# Started straight on the component, as if another system (AI, tutorial) had
	# put the player into aiming: the router owns no press for it, so it must not
	# stay live with nothing driving it.
	var component := _main.get_node("Player/Abilities") as GameplayAbilityComponent
	component.request_ability_preview(&"shot")
	var unowned := _count()
	await _frames(2)
	_check("unowned preview is auto-cancelled", unowned == 1 and _count() == 0,
		"during=%d after=%d" % [unowned, _count()])

	# --- 6. Dragging aims: past the dead zone the indicator follows the drag,
	#        inside it the skill keeps its default (auto-aim) direction --------
	await _frames(COOLDOWN_FRAMES)
	_router.press(0, Vector2.ZERO)
	var default_rotation := _indicator_rotation()
	_router.drag(0, Vector2(4.0, 0.0))
	await _frames(1)
	_check("a drag inside the dead zone keeps the default aim",
		is_equal_approx(_indicator_rotation(), default_rotation),
		"%f != %f" % [_indicator_rotation(), default_rotation])
	_router.drag(0, Vector2(0.0, 200.0))
	await _frames(1)
	_check("a drag past the dead zone aims the indicator",
		is_equal_approx(_indicator_rotation(), PI * 0.5), "rotation=%f" % _indicator_rotation())
	_router.release(0, Vector2(0.0, 200.0))
	_check("release after aiming clears the indicator", _count() == 0, "got %d" % _count())
	# Where the cast went matters as much as that it happened: a dragged cast must
	# follow the drag, not the auto-aim direction.
	await _frames(2)
	var dragged_shot := _first_projectile()
	_check("a dragged cast flies along the drag",
		dragged_shot != null and dragged_shot.direction.dot(Vector2.DOWN) > 0.99,
		"direction=%s" % [Vector2.ZERO if dragged_shot == null else dragged_shot.direction])

	# --- 7. A tap fires at the nearest enemy, not along `facing` ---------------
	# Regression: the activation context used to overwrite the preview's confirmed
	# direction with the router's raw drag direction, which is ZERO on a tap - the
	# projectile node then fell back to the caster's facing and fired backwards.
	await _frames(COOLDOWN_FRAMES)
	# The opposing team's group; teams replaced the old players/enemies groups.
	var enemy := Targets.nearest(_player, Teams.enemy_group_of(_player.team))
	var towards_enemy := (enemy.global_position - _player.global_position).normalized()
	_player.facing = -towards_enemy
	_router.press(0, Vector2.ZERO)
	_router.release(0, Vector2.ZERO)
	await _frames(2)
	var aimed_shot := _first_projectile()
	_check("a tap flies at the nearest enemy even when facing away",
		aimed_shot != null and aimed_shot.direction.dot(towards_enemy) > 0.99,
		"direction=%s expected=%s" % [
			Vector2.ZERO if aimed_shot == null else aimed_shot.direction, towards_enemy])

	# --- 8. Two casters of the same ability do not share preview state ---------
	# The plugin stores the preview (indicator node + caster + aim) on the ability
	# definition's `preview_strategy` resource, and a .tres holds a single instance:
	# without the per-caster copy (ability_loadout_2d.gd) the second caster's
	# begin() frees the first caster's indicator and its cancel() cancels whatever
	# started last - the multiplayer/AI-casting blocker (AGENTS.md pitfall 21).
	await _frames(COOLDOWN_FRAMES)	# the tap above put `shot` on cooldown
	var shot_definition := load("res://skills/data/player/shot/shot.tres") as GameplayAbilityDefinition
	var player_strategy := _router.ability_instance(0).get_definition().preview_strategy
	_check("a caster does not preview through the shared .tres strategy",
		player_strategy != shot_definition.preview_strategy)
	var second := _add_second_caster(Vector2(320.0, 140.0), shot_definition)
	var second_router := second.get_node("InputRouter") as AbilityInputRouter
	_check("a second caster gets its own strategy instance",
		second_router.ability_instance(0).get_definition().preview_strategy != player_strategy)
	_check("a fresh caster's strategy starts idle",
		not second_router.ability_instance(0).is_targeting())

	_router.press(0, Vector2.ZERO)
	second_router.press(0, Vector2.ZERO)
	await _frames(1)
	_check("two casters can aim at the same time", _count() == 2, "got %d" % _count())
	_check("each indicator sits on its own caster",
		_has_indicator_at(_player.global_position) and _has_indicator_at(second.global_position),
		"player=%s second=%s" % [_player.global_position, second.global_position])

	# Cancelling one caster must leave the other aiming - and leave *its* indicator.
	second_router.cancel_aim()
	await _frames(1)
	_check("cancelling one caster leaves the other's indicator", _count() == 1, "got %d" % _count())
	_check("the surviving indicator belongs to the player",
		_has_indicator_at(_player.global_position) and not _has_indicator_at(second.global_position))
	_router.cancel_aim()
	_check("no indicator left after both casters stop", _count() == 0, "got %d" % _count())
	second.queue_free()

	# --- 9. Swapping the equipped ability while aiming -----------------------
	await _frames(COOLDOWN_FRAMES)
	_router.press(0, at)
	_check("press before equip: one indicator", _count() == 1, "got %d" % _count())
	# Dash is the one ability every hero carries, so it is the swappable one.
	_router.equip(0, &"dash")
	_check("equip releases the indicator", _count() == 0, "got %d" % _count())

# --- helpers ----------------------------------------------------------------
## Live indicators only. Counted by class, not by the `skill_indicators` group:
## that group is a debugging aid added together with the fix, so the suite must
## not depend on it - it has to fail on the code that had the bug. Indicators are
## added to the current scene in world space, and a queue_free()d node stays in
## the tree until the end of the frame, so skip those.
func _count() -> int:
	var count := 0
	for child in get_tree().current_scene.get_children():
		if child is SkillIndicator and not child.is_queued_for_deletion():
			count += 1
	return count

## The two events one finger produces. Fed straight to the button, so the check
## does not depend on window size or on the GUI hit test.
func _touch_press(at: Vector2) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = at
	event.pressed = true
	return event

func _touch_release(at: Vector2) -> InputEventScreenTouch:
	var event := _touch_press(at)
	event.pressed = false
	return event

func _mouse_press(at: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = at
	event.pressed = true
	return event

func _mouse_release(at: Vector2) -> InputEventMouseButton:
	var event := _mouse_press(at)
	event.pressed = false
	return event

## A minimal second caster: a Node2D with the plugin's ability component plus a
## game router, learning the *same* ability definition the player has.
func _add_second_caster(at: Vector2, definition: GameplayAbilityDefinition) -> Node2D:
	var caster := Node2D.new()
	caster.name = "SecondCaster"
	var component := GameplayAbilityComponent.new()
	# get_component_by_interface() falls back to a child with the component's name.
	component.name = "GameplayAbilityComponent"
	caster.add_child(component)
	var loadout := AbilityLoadout2D.new()
	var abilities: Array[GameplayAbilityDefinition] = [definition]
	loadout.abilities = abilities
	var router := AbilityInputRouter.new()
	router.name = "InputRouter"
	router.loadout = loadout
	# Add the router last: its _ready() looks the component up on its parent.
	caster.add_child(router)
	_main.add_child(caster)
	caster.global_position = at
	return caster

## True when a live indicator sits exactly on `point` (arrow indicators are placed
## on their caster).
func _has_indicator_at(point: Vector2) -> bool:
	for child in get_tree().current_scene.get_children():
		if child is SkillIndicator and not child.is_queued_for_deletion():
			if (child as SkillIndicator).global_position.distance_to(point) < 1.0:
				return true
	return false

## The most recent live projectile: fired skills spawn next to the caster, so they
## are children of this arena.
func _first_projectile() -> Projectile:
	for child in _main.get_children():
		if child is Projectile and not child.is_queued_for_deletion():
			return child
	return null

## Rotation of the live indicator, or NAN when there is none (is_equal_approx()
## then fails the check instead of silently passing).
func _indicator_rotation() -> float:
	for child in get_tree().current_scene.get_children():
		if child is SkillIndicator and not child.is_queued_for_deletion():
			return (child as SkillIndicator).rotation
	return NAN

## Bots fire on their own; tests drive damage themselves, so their routers are muted.
func _silence_bots() -> void:
	for unit in get_tree().get_nodes_in_group(&"units"):
		var router := unit.get_node_or_null("AiRouter")
		if router != null:
			router.set_process(false)

func _check(label: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	if not passed:
		_failed += 1
	print("%s | %s%s" % ["PASS" if passed else "FAIL", label, "" if detail.is_empty() else "  <- " + detail])

## Not a check: the scenario cannot be exercised in this run.
func _skip(label: String, reason: String) -> void:
	print("SKIP | %s  (%s)" % [label, reason])

func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame
