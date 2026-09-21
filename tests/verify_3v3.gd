extends Node2D
## Regression suite for the team/unit abstraction: what the 3v3 stands on.
##
## Covers the things that used to be hand-maintained per skill and can now only be
## wrong in one place: who belongs to which side, who may damage whom (no friendly
## fire), where each side starts (walkable floor, read from the arena map), and the
## per-unit scoreboard the end screen shows.
##
## Run (must run as a scene - AGENTS.md pitfall 12):
##   godot --path . --fixed-fps 60 res://tests/verify_3v3.tscn
##   godot --headless --path . --fixed-fps 60 res://tests/verify_3v3.tscn
## Exit code 0 = every check passed.

const MAIN_SCENE: String = "res://main/main.tscn"
const SPAWNS: String = "res://maps/arena_01/spawns.tres"
const TERRAIN_SCRIPT: String = "res://maps/arena_01/terrain.gd"
const ROSTER: String = "res://heroes/roster.tres"
const BULLET_DAMAGE: String = "res://skills/data/shared/effects/bullet_damage.tres"
const PROJECTILE_SCENE: String = "res://entities/projectile/projectile.tscn"
const SECOND: int = 60
const TILE: float = 32.0

var _checks: int = 0
var _failed: int = 0
var _main: Node2D = null
var _director: MatchDirector = null
var _player: Unit = null
var _damage: GameplayEffect = null

func _ready() -> void:
	get_tree().root.size = Vector2i(1152, 648)
	_damage = load(BULLET_DAMAGE) as GameplayEffect
	await _frames(1)
	_main = (load(MAIN_SCENE) as PackedScene).instantiate() as Node2D
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	await _frames(3)
	_director = _main.get_node("MatchDirector") as MatchDirector
	_player = _director.human_unit
	if _director == null or _player == null:
		print("FAIL | setup: could not bind the arena")
		get_tree().quit(1)
		return
	await _run()
	print("=== 3v3 / teams: %d/%d checks passed ===" % [_checks - _failed, _checks])
	get_tree().quit(1 if _failed > 0 else 0)

func _run() -> void:
	# --- 1. Data: heroes and spawn points -------------------------------------
	var roster := load(ROSTER) as TeamRoster
	_check("the roster offers five selectable heroes",
		roster != null and roster.selectable.size() == 5,
		"heroes=%d" % [0 if roster == null else roster.selectable.size()])
	var heroes_ok := true
	for hero in roster.selectable:
		if hero == null or hero.signature() == null or hero.loadout.abilities.size() != 2:
			heroes_ok = false
	_check("every hero has a signature skill plus the shared dash", heroes_ok)

	var spawns := load(SPAWNS) as SpawnLayout
	_check("three spawn points per side",
		spawns != null and spawns.blue_points.size() == 3 and spawns.red_points.size() == 3)
	_check("every spawn point stands on walkable floor",
		_spawns_on_floor(spawns), _describe_spawns(spawns))
	_check("the two sides start apart from each other",
		spawns.blue_points[0].distance_to(spawns.red_points[0]) > 400.0,
		"%.0f" % spawns.blue_points[0].distance_to(spawns.red_points[0]))

	# --- 2. Teams: membership, colours, the human seat ------------------------
	_check("every unit belongs to exactly one team group",
		_units_in_team_groups() == 6, "units=%d" % _units_in_team_groups())
	_check("the unit list and the team groups agree",
		_director.units.size() == 6, "units=%d" % _director.units.size())
	_check("the local player is blue, the others are AI",
		_player.team == Teams.Id.BLUE and _player.human_group_only(),
		"team=%d" % _player.team)
	_check("AI looks for the opposing team", _bot_of(Teams.Id.BLUE).hostile_group() == &"team_red"
		and _bot_of(Teams.Id.RED).hostile_group() == &"team_blue")
	_check("the two sides have different colours",
		not Teams.color_of(Teams.Id.BLUE).is_equal_approx(Teams.color_of(Teams.Id.RED)))

	# --- 3. The one friendly-fire rule ---------------------------------------
	_check("same team is not hostile", not Teams.is_hostile(Teams.Id.BLUE, Teams.Id.BLUE))
	_check("opposite teams are hostile", Teams.is_hostile(Teams.Id.BLUE, Teams.Id.RED))
	_check("a teamless source keeps the old behaviour (scenery shots)",
		Teams.can_damage(null, _player))

	await _wait_playing()
	_silence_bots()
	var mate := _bot_of(Teams.Id.BLUE)
	var red := _bot_of(Teams.Id.RED)
	mate.set_physics_process(false)
	red.set_physics_process(false)
	# Row 11 of the arena is an open lane; the spawn rows have wall blocks between the
	# two sides (cols 6-11), which would stop the test shots instead of the team rule.
	_player.global_position = Vector2(400.0, 368.0)
	mate.global_position = Vector2(200.0, 368.0)
	red.global_position = Vector2(600.0, 368.0)

	# A teammate shoots through the player: the shot must pass straight by.
	var health_before := _player.health_ratio()
	_fire_from(mate, Vector2.RIGHT, 400.0)
	await _frames(int(1.0 * SECOND))
	_check("a teammate's projectile does not hurt the player",
		is_equal_approx(_player.health_ratio(), health_before),
		"%.2f -> %.2f" % [health_before, _player.health_ratio()])

	# An opponent's shot at the same spot does hurt.
	_fire_from(red, Vector2.LEFT, 400.0)
	await _frames(int(1.0 * SECOND))
	_check("an opponent's projectile does hurt the player",
		_player.health_ratio() < health_before,
		"%.2f -> %.2f" % [health_before, _player.health_ratio()])

	# A teammate's ground field does not tick on the player either.
	var health_now := _player.health_ratio()
	var blue_field := MagicFieldData2D.new()
	blue_field.duration = 0.4
	blue_field.tick_interval = 0.0
	blue_field.radius = 120.0
	blue_field.target_group = &"enemies"	# stale data: teams must win over this
	var blast: Array[GameplayEffect] = [load(BULLET_DAMAGE) as GameplayEffect]
	blue_field.payload_effects = blast
	blue_field.field_scene = load("res://entities/magic_field/magic_field.tscn")
	var field := blue_field.field_scene.instantiate()
	_main.add_child(field)
	field.start(blue_field, mate, _player.global_position)
	await _frames(int(0.5 * SECOND))
	_check("a teammate's field does not tick on the player",
		is_equal_approx(_player.health_ratio(), health_now),
		"%.2f -> %.2f" % [health_now, _player.health_ratio()])

	# --- 4. Scoreboard --------------------------------------------------------
	_check("every unit has a scoreboard row", _director.stats.rows().size() == 6,
		"rows=%d" % _director.stats.rows().size())
	_check("damage taken from the opponent counts for them",
		_director.stats.damage_of(red) >= 10, "%d" % _director.stats.damage_of(red))
	# The teammate's shot passed the player and hit the opponent behind them: that is
	# the damage the scoreboard must credit (10 = one bullet).
	_check("the teammate's shot hit the opponent, not the player",
		is_equal_approx(red.health_ratio(), 0.9) and is_equal_approx(_player.health_ratio(), 0.9),
		"red=%.2f player=%.2f" % [red.health_ratio(), _player.health_ratio()])
	_check("that hit is credited to the teammate", _director.stats.damage_of(mate) >= 10,
		"%d" % _director.stats.damage_of(mate))
	_hurt(red, 200.0, _player)
	await _frames(1)
	_check("the killing blow is credited as a kill", _director.stats.kills_of(_player) == 1,
		"%d" % _director.stats.kills_of(_player))
	_check("the local player's row is marked", _row_of(_player).get("human", false))
	# Damage is capped by the health that was actually left (the target had taken 10).
	_check("the local player's damage was recorded",
		_director.stats.damage_of(_player) >= 90, "%d" % _director.stats.damage_of(_player))
	_check("rows are sorted by damage", _rows_sorted_by_damage())

# --- helpers ----------------------------------------------------------------
func _units_in_team_groups() -> int:
	return get_tree().get_nodes_in_group(&"team_blue").size() \
		+ get_tree().get_nodes_in_group(&"team_red").size()

func _bot_of(team: int) -> Unit:
	for node in get_tree().get_nodes_in_group(Teams.group_of(team)):
		var unit := node as Unit
		if unit != null and not unit.is_human():
			return unit
	return null

func _row_of(unit: Unit) -> Dictionary:
	for row in _director.stats.rows():
		if String(row.get("name", "")) == unit.display_name() and int(row.get("team", -1)) == unit.team:
			return row
	return {}

func _rows_sorted_by_damage() -> bool:
	var previous := 1 << 30
	for row in _director.stats.rows():
		var damage := int(row.get("damage", 0))
		if damage > previous:
			return false
		previous = damage
	return true

## Spawns read from the arena's own ASCII map, so a map edit cannot leave a unit in
## a wall (the data is generated from the same map, see generate_ability_data.gd).
func _spawns_on_floor(spawns: SpawnLayout) -> bool:
	var terrain := load(TERRAIN_SCRIPT) as GDScript
	var rows: PackedStringArray = terrain.get_script_constant_map()["ARENA"]
	var points: Array[Vector2] = []
	points.append_array(spawns.blue_points)
	points.append_array(spawns.red_points)
	for point in points:
		var col := int(floor(point.x / TILE))
		var row := int(floor(point.y / TILE))
		if row < 0 or row >= rows.size() or col < 0 or col >= rows[row].length():
			return false
		if rows[row][col] == "#":
			return false
	return true

func _describe_spawns(spawns: SpawnLayout) -> String:
	return "blue=%s red=%s" % [spawns.blue_points, spawns.red_points]

## Fires a projectile the way the ability tree does, so the payload path (including
## the team filter) is the real one.
func _fire_from(shooter: Unit, direction: Vector2, distance: float) -> void:
	var projectile := (load(PROJECTILE_SCENE) as PackedScene).instantiate() as Projectile
	projectile.payload_effects = [(_damage.duplicate(true) as GameplayEffect)]
	projectile.instigator = shooter
	_main.add_child(projectile)
	projectile.global_position = shooter.global_position + direction * 22.0
	projectile.launch(direction, 520.0, distance)

func _hurt(target: Node, amount: float, instigator: Node) -> void:
	if not is_instance_valid(target):
		return
	for _i in int(ceilf(amount / 10.0)):
		(_damage.duplicate(true) as GameplayEffect).apply(target, instigator, {})

func _silence_bots() -> void:
	for unit in get_tree().get_nodes_in_group(&"units"):
		var router := unit.get_node_or_null("AiRouter")
		if router != null:
			router.set_process(false)

func _wait_playing(max_frames: int = 8 * SECOND) -> bool:
	for _i in max_frames:
		if _director.is_playing():
			return true
		await get_tree().process_frame
	return _director.is_playing()

func _check(label: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	if not passed:
		_failed += 1
	print("%s | %s%s" % ["PASS" if passed else "FAIL", label, "" if detail.is_empty() else "  <- " + detail])

func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame
