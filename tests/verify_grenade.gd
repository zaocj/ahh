extends Node2D
## Regression suite for the grenade (bomb): pick a spot inside the reach
## ring, the bomb is thrown there and blasts it for high damage.
##
## Run (must run as a scene - AGENTS.md pitfall 12):
##   godot --path . --fixed-fps 60 res://tests/verify_grenade.tscn
##   godot --headless --path . --fixed-fps 60 res://tests/verify_grenade.tscn
## Exit code 0 = every check passed.
##
## The enemy is frozen (no chase, no AI) so "where did it land" is exact, and the
## drag distances are derived from the preview strategy's own mapping
## (full_drag_pixels -> max_range) instead of hard-coded pixel magic.

const MAIN_SCENE: String = "res://main/main.tscn"
const BOMB_DEFINITION: String = "res://skills/data/player/bomb/bomb_skill.tres"
const SECOND: int = 60

var _checks: int = 0
var _failed: int = 0
var _main: Node2D = null
var _director: MatchDirector = null
var _player: Unit = null
var _enemy: Unit = null
var _router: AbilityInputRouter = null
## Reach of the throw and the pointer distance that maps to it (from the data).
var _max_range: float = 420.0
var _full_drag_pixels: float = 240.0
var _blast_radius: float = 95.0

func _ready() -> void:
	get_tree().root.size = Vector2i(1152, 648)
	# The grenade belongs to the bomber; pick it the way the hero screen does, so the
	# local seat spawns with it in slot 0.
	MatchConfig.selected_hero = load("res://heroes/bomber/bomber_data.tres")
	await _frames(1)
	_main = (load(MAIN_SCENE) as PackedScene).instantiate() as Node2D
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	await _frames(2)
	_bind()
	if _router == null:
		print("FAIL | setup: could not bind the arena")
		get_tree().quit(1)
		return
	var definition := load(BOMB_DEFINITION) as GameplayAbilityDefinition
	if definition != null and definition.preview_strategy is IndicatorPreview2D:
		var preview := definition.preview_strategy as IndicatorPreview2D
		_max_range = preview.max_range
		_full_drag_pixels = preview.full_drag_pixels
	await _run()
	print("=== grenade: %d/%d checks passed ===" % [_checks - _failed, _checks])
	get_tree().quit(1 if _failed > 0 else 0)

func _bind() -> void:
	_main = get_tree().current_scene as Node2D
	_director = _main.get_node("MatchDirector") as MatchDirector
	_player = _main.get_node("Player") as Unit
	_enemy = _first_hostile()
	_router = _player.get_node("InputRouter") as AbilityInputRouter

func _run() -> void:
	# A quiet, deterministic arena: the enemy neither shoots nor walks.
	_silence_bots()
	_enemy.set_physics_process(false)
	# The 3v3 spawns start a screen apart; the grenade reaches 420px, so put the
	# target inside the ring (frozen, so everything stays deterministic).
	_enemy.global_position = _player.global_position + Vector2(300.0, 0.0)
	_director.match_seconds = 600.0
	_director.start()
	await _wait_playing()

	# --- 1. The grenade can be equipped and shows reach + blast ----------------
	_check("the bomber spawns with its signature skill in slot 0",
		_router.ability_id(0) == &"bomb", String(_router.ability_id(0)))

	_router.press(0, Vector2.ZERO)
	await _frames(1)
	_check("aiming shows a blast circle and a reach ring", _count() == 2, "got %d" % _count())
	_check("the reach ring is centred on the caster", _has_indicator_at(_player.global_position),
		"player=%s indicators=%s" % [_player.global_position, _positions()])
	_check("a tap starts the blast circle on the nearest enemy",
		_has_indicator_at(_enemy.global_position),
		"enemy=%s indicators=%s" % [_enemy.global_position, _positions()])
	_router.cancel_aim()
	_check("cancelling clears both indicators", _count() == 0, "got %d" % _count())

	# --- 2. The drag length picks the landing distance -------------------------
	# A short drag must land close, a long one is clamped to the reach.
	var short_distance := _max_range * 0.25
	_router.press(0, Vector2.ZERO)
	_router.drag(0, Vector2(_drag_for(short_distance), 0.0))
	await _frames(1)
	var expected_short := _player.global_position + Vector2(short_distance, 0.0)
	_check("a short drag places the blast close",
		_blast_is_at(expected_short), "expected=%s got=%s" % [expected_short, _positions()])

	_router.drag(0, Vector2(_drag_for(_max_range * 4.0), 0.0))
	await _frames(1)
	var expected_far := _player.global_position + Vector2(_max_range, 0.0)
	_check("a drag beyond the ring is clamped to the reach",
		_blast_is_at(expected_far), "expected=%s got=%s" % [expected_far, _positions()])
	_router.cancel_aim()

	# --- 3. The bomb lands exactly where it was aimed --------------------------
	var chosen_distance := _max_range * 0.5
	await _throw(Vector2(_drag_for(chosen_distance), 0.0))
	var chosen_spot := _player.global_position + Vector2(chosen_distance, 0.0)
	_check("the explosion happens at the chosen spot", _field_is_at(chosen_spot),
		"expected=%s got=%s" % [chosen_spot, _field_position()])
	# The blast is a ground decal: it must draw above the floor, or y-sorting lets
	# tiles bite a chunk out of the circle (that is what Terrain z_index = -10 is for).
	var terrain := _main.get_node("Arena01/Terrain") as CanvasItem
	var field := _field()
	_check("the blast draws above the floor", field != null and field.z_index > terrain.z_index,
		"field=%s terrain=%s" % [
			"<none>" if field == null else str(field.z_index), str(terrain.z_index)])
	_check("no indicator is left after the throw", _count() == 0, "got %d" % _count())

	# --- 4. High damage, only inside the blast ---------------------------------
	# A tap aims the blast at the enemy (the arena's only target).
	var before := _enemy.health_ratio()
	var player_before := _player.health_ratio()
	await _frames(int(2.1 * SECOND))	# 2s cooldown
	await _throw(_drag_towards_enemy(_distance_to_enemy()))
	_check("the blast takes 25 health off the target",
		is_equal_approx(before - _enemy.health_ratio(), 0.25),
		"%.2f -> %.2f" % [before, _enemy.health_ratio()])
	_check("the blast does not hurt the thrower",
		is_equal_approx(_player.health_ratio(), player_before),
		"%.2f -> %.2f" % [player_before, _player.health_ratio()])

	# --- 5. It flies over bodies instead of exploding on them ------------------
	# Land it well past the enemy: a projectile that detonated on contact would
	# damage it, a lobbed throw sails on and only blasts the landing spot.
	var enemy_health := _enemy.health_ratio()
	var gap := _distance_to_enemy()
	_check("there is room for the fly-over check", gap > 2.0 * _blast_radius,
		"gap=%.1f blast=%.1f" % [gap, _blast_radius])
	await _frames(int(2.1 * SECOND))
	var far_distance := minf(gap * 1.6, _max_range)
	await _throw(_drag_towards_enemy(far_distance))
	_check("the bomb sails past the enemy without touching it",
		is_equal_approx(_enemy.health_ratio(), enemy_health),
		"%.2f -> %.2f" % [enemy_health, _enemy.health_ratio()])
	_check("the explosion still happened at the far spot",
		_field_is_at(_player.global_position
			+ Vector2.from_angle(_direction_to_enemy_angle()) * far_distance),
		"got=%s" % _field_position())

	# --- 6. Cooldown ----------------------------------------------------------
	_check("the throw went on cooldown", not _router.is_ready(0))
	_router.press(0, Vector2.ZERO)
	await _frames(1)
	_check("a second throw is refused while cooling down", _count() == 0, "got %d" % _count())

# --- helpers ----------------------------------------------------------------
## Pointer drag (pixels) that the strategy maps to `distance` in world units.
func _drag_for(distance: float) -> float:
	return clampf(distance / maxf(_max_range, 1.0), 0.0, 1.0) * _full_drag_pixels

## Pointer offset that throws `distance` world units towards the enemy.
func _drag_towards_enemy(distance: float) -> Vector2:
	return Vector2.from_angle(_direction_to_enemy_angle()) * _drag_for(distance)

func _direction_to_enemy_angle() -> float:
	return (_enemy.global_position - _player.global_position).angle()

func _distance_to_enemy() -> float:
	return _player.global_position.distance_to(_enemy.global_position)

## Press, drag, release, then wait until the explosion actually happens (bounded),
## so the checks never race the flight time. `aim` is a pointer offset, and the
## strategy maps its length to world units.
func _throw(aim: Vector2) -> void:
	_router.press(0, Vector2.ZERO)
	_router.drag(0, aim)
	_router.release(0, aim)
	for _i in 2 * SECOND:
		if _field() != null:
			return
		await get_tree().process_frame

func _count() -> int:
	var count := 0
	for child in get_tree().current_scene.get_children():
		if child is SkillIndicator and not child.is_queued_for_deletion():
			count += 1
	return count

func _positions() -> Array[Vector2]:
	var found: Array[Vector2] = []
	for child in get_tree().current_scene.get_children():
		if child is SkillIndicator and not child.is_queued_for_deletion():
			found.append((child as SkillIndicator).global_position)
	return found

func _has_indicator_at(point: Vector2) -> bool:
	for position in _positions():
		if position.distance_to(point) < 12.0:
			return true
	return false

## The blast circle is the indicator that is *not* on the caster.
func _blast_is_at(expected: Vector2) -> bool:
	for position in _positions():
		if position.distance_to(_player.global_position) > 1.0 and position.distance_to(expected) < 6.0:
			return true
	return false

func _field_position() -> Vector2:
	var field := _field()
	return Vector2.ZERO if field == null else field.global_position

func _field_is_at(expected: Vector2) -> bool:
	var field := _field()
	return field != null and field.global_position.distance_to(expected) < 10.0

## The blast is a MagicField2D spawned next to the projectile's parent (the arena).
func _field() -> MagicField2D:
	for child in _main.get_children():
		if child is MagicField2D and not child.is_queued_for_deletion():
			return child
	return null

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
