class_name UnitCamera
extends Camera2D
## The game camera: follows the unit the player controls, or the teammate they are
## spectating, plus screen shake.
##
## It lives in the arena and *follows* a unit instead of being a child of one:
## switching who you watch (death -> living teammate) is then a single assignment,
## with no re-parenting - and a Camera2D switches itself off when it leaves the tree,
## which makes re-attaching it a trap.
##
## Shake is trauma based: events add trauma, trauma decays, and the offset scales with
## trauma squared - so a single hit is a nudge and a death lands hard. The path is a
## smooth sum of sines instead of per-frame randomness, which reads as a shake rather
## than a jitter (and stays deterministic for tests).

@export_group("Follow")
## Unit the camera rides on; assigned by the match (spawn, then spectating).
@export var follow: Node2D = null

@export_group("Shake")
## Trauma added when the watched unit itself is hit.
@export var player_hit_trauma: float = 0.45
## Trauma added when an enemy dies nearby.
@export var enemy_death_trauma: float = 0.25
## Trauma lost per second; a hit is over in roughly half a second.
@export var trauma_decay: float = 1.8
## Maximum offset at full trauma.
@export var max_offset: Vector2 = Vector2(20.0, 14.0)
## Maximum roll at full trauma, in radians.
@export var max_roll: float = 0.05
## Shake speed.
@export var frequency: float = 16.0
## Enemy deaths further away than this do not shake the screen.
@export var near_radius: float = 700.0

var _trauma: float = 0.0
var _time: float = 0.0

func _ready() -> void:
	enabled = true
	make_current()
	CombatEvents.damaged.connect(_on_damaged)
	CombatEvents.died.connect(_on_died)

## Watch another unit (spawn, or the next teammate after a death).
func setup(unit: Node2D) -> void:
	follow = unit
	if is_instance_valid(follow):
		# Snap instead of smoothing across the arena when the target changes.
		global_position = follow.global_position

func _physics_process(_delta: float) -> void:
	if is_instance_valid(follow):
		global_position = follow.global_position

## Adds trauma (clamped to 0..1). Public so other presentation code can ask for a
## shake without knowing how it is implemented.
func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)

func trauma() -> float:
	return _trauma

func _on_damaged(victim: Node2D, _amount: float, _source: Node) -> void:
	# Only being hit ourselves shakes the screen; our own hits read through the
	# damage number and the sound instead.
	if victim != null and victim == follow:
		add_trauma(player_hit_trauma)

func _on_died(entity: Node2D, _source: Node) -> void:
	if not is_instance_valid(entity):
		return
	if entity.is_in_group(Teams.group_of(Teams.Id.RED)) \
			and entity.global_position.distance_to(global_position) < near_radius:
		add_trauma(enemy_death_trauma)

func _process(delta: float) -> void:
	if _trauma <= 0.0:
		# Release the camera exactly back to normal, so nothing drifts.
		if offset != Vector2.ZERO or not is_zero_approx(rotation):
			offset = Vector2.ZERO
			rotation = 0.0
		return
	_trauma = maxf(_trauma - trauma_decay * delta, 0.0)
	_time += delta
	var amount := _trauma * _trauma
	var wobble := Vector2(
		sin(_time * frequency) + 0.5 * sin(_time * frequency * 2.31),
		cos(_time * frequency * 1.37) + 0.5 * cos(_time * frequency * 3.11))
	offset = wobble * max_offset * amount * 0.66
	rotation = max_roll * amount * sin(_time * frequency * 0.83)
