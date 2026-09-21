extends Node2D
## Regression suite for combat feedback: damage numbers, hit flash, screen
## shake and placeholder audio.
##
## Run (must run as a scene - AGENTS.md pitfall 12):
##   godot --path . --fixed-fps 60 res://tests/verify_feedback.tscn
##   godot --headless --path . --fixed-fps 60 res://tests/verify_feedback.tscn
## Exit code 0 = every check passed.
##
## Damage is applied through the real effect the bullets carry, so the whole
## gameplay -> bus -> presentation chain is exercised, not a mock.

const MAIN_SCENE: String = "res://main/main.tscn"
const BULLET_DAMAGE: String = "res://skills/data/shared/effects/bullet_damage.tres"
const HIT_WAV: String = "res://assets/audio/hit.wav"
const PLAYER_HIT_WAV: String = "res://assets/audio/player_hit.wav"
const SHOOT_WAV: String = "res://assets/audio/shoot.wav"
const SECOND: int = 60

var _checks: int = 0
var _failed: int = 0
var _main: Node2D = null
var _director: MatchDirector = null
var _player: Unit = null
var _enemy: Unit = null
var _numbers: DamageNumbers = null
var _sfx: CombatSfx = null
var _camera: UnitCamera = null
var _router: AbilityInputRouter = null
var _damage: GameplayEffect = null

func _ready() -> void:
	get_tree().root.size = Vector2i(1152, 648)
	_damage = load(BULLET_DAMAGE) as GameplayEffect
	await _frames(1)
	_main = (load(MAIN_SCENE) as PackedScene).instantiate() as Node2D
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	await _frames(2)
	_bind()
	if _numbers == null or _sfx == null or _camera == null:
		print("FAIL | setup: the feedback nodes are missing from main.tscn")
		get_tree().quit(1)
		return
	await _run()
	print("=== combat feedback: %d/%d checks passed ===" % [_checks - _failed, _checks])
	get_tree().quit(1 if _failed > 0 else 0)

func _bind() -> void:
	_main = get_tree().current_scene as Node2D
	_director = _main.get_node("MatchDirector") as MatchDirector
	_player = _main.get_node("Player") as Unit
	_enemy = _first_hostile()
	_numbers = _main.get_node_or_null("DamageNumbers") as DamageNumbers
	_sfx = _main.get_node_or_null("CombatSfx") as CombatSfx
	_camera = _main.get_node_or_null("Camera") as UnitCamera
	_router = _player.get_node("InputRouter") as AbilityInputRouter

func _run() -> void:
	# A quiet arena: no enemy fire, no clock running out under the checks.
	_silence_bots()
	_director.match_seconds = 600.0
	_director.start()
	await _wait_playing()

	# --- 1. A hit spawns exactly one floating number that cleans itself up -----
	_check("no numbers before any hit", _number_count() == 0, "got %d" % _number_count())
	_hurt(_enemy, 10.0, _player)
	await _frames(1)
	_check("a hit spawns one damage number", _number_count() == 1, "got %d" % _number_count())
	var number := _first_number()
	_check("the number shows the damage that got through",
		number != null and number.display_text() == "10",
		"text=%s" % ["<none>" if number == null else number.display_text()])
	_check("the number starts above the victim's health bar",
		number != null and number.global_position.distance_to(_enemy.global_position + Vector2(0.0, -38.0)) < 20.0,
		"offset=%s" % [Vector2.ZERO if number == null else number.global_position - _enemy.global_position])
	await _frames(int(1.2 * SECOND))
	_check("the number frees itself after its lifetime", _number_count() == 0, "got %d" % _number_count())

	# --- 2. Hit flash (the victim whitens for a moment) -------------------------
	_hurt(_enemy, 10.0, _player)
	await _frames(1)
	var body := _enemy.get_node("Body") as Polygon2D
	# The flash tween starts at white and is already fading one frame later, so
	# compare against the body's own red instead of exact white.
	_check("a hit flashes the victim white", body.color.g > 0.8 and body.color.b > 0.8,
		str(body.color))
	await _frames(int(0.3 * SECOND))
	_check("the flash fades back to the body colour",
		not body.color.is_equal_approx(Color(1.0, 1.0, 1.0)), str(body.color))

	# --- 3. Screen shake -------------------------------------------------------
	_check("the camera starts steady", _camera.trauma() <= 0.0 and _camera.offset == Vector2.ZERO)
	_hurt(_player, 10.0, _enemy)
	_check("being hit adds camera trauma", _camera.trauma() > 0.0,
		"trauma=%f" % _camera.trauma())
	await _frames(3)
	_check("trauma moves the camera", _camera.offset.length() > 0.0001,
		"offset=%s" % _camera.offset)
	await _frames(int(1.0 * SECOND))
	_check("the shake decays back to a steady camera",
		_camera.trauma() <= 0.0 and _camera.offset == Vector2.ZERO,
		"trauma=%f offset=%s" % [_camera.trauma(), _camera.offset])

	# --- 4. Placeholder audio --------------------------------------------------
	# Each check reads the stream the event just requested, so it cannot be fooled
	# by whatever played before (events are reported synchronously).
	_hurt(_enemy, 10.0, _player)
	_check("a hit on an enemy plays the hit sound",
		_sfx.last_stream() == load(HIT_WAV), _stream_name(_sfx.last_stream()))
	_hurt(_player, 10.0, _enemy)
	_check("a hit on the player plays the player-hit sound",
		_sfx.last_stream() == load(PLAYER_HIT_WAV), _stream_name(_sfx.last_stream()))
	# Let the numbers from those two hits expire before checking the cast path.
	await _frames(int(1.0 * SECOND))
	_router.press(0, Vector2.ZERO)
	_router.release(0, Vector2.ZERO)
	_check("casting plays the cast sound",
		_sfx.last_stream() == load(SHOOT_WAV), _stream_name(_sfx.last_stream()))
	_check("a cast alone spawns no damage number", _number_count() == 0, "got %d" % _number_count())
	await _frames(2)
	_check("audio actually started playing", not _sfx.playing_streams().is_empty(),
		"playing=%d" % _sfx.playing_streams().size())

	# --- 5. Death and match-result feedback ------------------------------------
	var death_stream := _sfx.death_stream
	var lose_stream := _sfx.lose_stream
	_hurt(_player, 200.0, _enemy)
	await _frames(1)
	# Dying and finishing the match are the same frame: the death sound is on one
	# voice, the result sting on another, so both have to be playing.
	# `playing` is not a witness here: the death and the result sting are requested
	# in the same burst and a 0.5s sound can already be over by the next frame
	# (headless has no real audio clock). The play history records what was asked for.
	_check("death plays the death sound", _sfx.play_history().has(death_stream),
		_stream_name(death_stream))
	_check("the player's death spawns its own damage number", _number_count() >= 1,
		"got %d" % _number_count())
	# Losing one unit no longer ends a 3v3: the whole team has to fall before the
	# match-result sting plays.
	for mate in get_tree().get_nodes_in_group(Teams.group_of(Teams.Id.BLUE)):
		_hurt(mate, 200.0, _enemy)
	await _frames(1)
	_check("wiping the team ends the match with the result sound",
		_sfx.play_history().has(lose_stream), _stream_name(_sfx.last_stream()))

# --- helpers ----------------------------------------------------------------
func _number_count() -> int:
	var count := 0
	for child in _numbers.get_children():
		if child is DamageNumber and not child.is_queued_for_deletion():
			count += 1
	return count

func _first_number() -> DamageNumber:
	for child in _numbers.get_children():
		if child is DamageNumber and not child.is_queued_for_deletion():
			return child
	return null

func _stream_name(stream: AudioStream) -> String:
	return "<none>" if stream == null else stream.resource_path

## Applies the effect the bullets carry - the real damage path, not a vital poke.
func _hurt(target: Node, amount: float, instigator: Node) -> void:
	if not is_instance_valid(target):
		return
	for _i in int(ceilf(amount / 10.0)):
		(_damage.duplicate(true) as GameplayEffect).apply(target, instigator, {})

func _wait_playing(max_frames: int = 8 * SECOND) -> bool:
	for _i in max_frames:
		if _director.is_playing():
			return true
		await get_tree().process_frame
	return _director.is_playing()

## The first unit of the opposing team: what used to be "the enemy".
func _first_hostile() -> Unit:
	return get_tree().get_first_node_in_group(&"team_red") as Unit

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

func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame
