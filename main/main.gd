extends Node2D
## Arena root: wires the on-screen controls (movement joystick, ability buttons,
## skill drawer, enemy spawner) to the player and reports state on the HUD.
##
## Skills are handled by the gameplay ability system plugin; this script only
## routes button presses into it and mirrors cooldowns back onto the buttons.

@onready var player: Player = $Player
@onready var joystick: Control = $HUD/Joystick
@onready var status_label: Label = $HUD/Status
@onready var skill_buttons: Array[SkillButton] = [$HUD/SkillBullet, $HUD/SkillDash]
@onready var ability_input: AbilityInputRouter = $Player/InputRouter
@onready var drawer: SkillDrawer = $HUD/SkillDrawer
@onready var drawer_toggle: ActionButton = $HUD/DrawerToggle
@onready var spawn_button: ActionButton = $HUD/SpawnEnemy

const HINT: String = "WASD / Arrows or drag the joystick to move | tap a skill to cast, hold to aim"
const ENEMY_SCENE: String = "res://entities/enemy/enemy.tscn"
## Clear floor cells the spawner cycles through.
const SPAWN_POINTS: Array[Vector2] = [
	Vector2(200.0, 150.0),
	Vector2(400.0, 150.0),
	Vector2(1000.0, 150.0),
	Vector2(1000.0, 600.0),
	Vector2(200.0, 600.0),
]

var _spawn_index: int = 0

func _ready() -> void:
	joystick.vector_changed.connect(_on_joystick_vector_changed)
	status_label.text = HINT
	_wire_skill_buttons()
	drawer.setup(ability_input)
	drawer.ability_chosen.connect(_on_ability_chosen)
	drawer_toggle.pressed.connect(drawer.toggle)
	spawn_button.pressed.connect(spawn_enemy)

func _process(_delta: float) -> void:
	for slot in skill_buttons.size():
		skill_buttons[slot].set_cooldown_ratio(ability_input.cooldown_ratio(slot))

## Buttons and ability slots share their order: button i drives slot i.
func _wire_skill_buttons() -> void:
	for slot in skill_buttons.size():
		var button := skill_buttons[slot]
		button.pressed_at.connect(func(position: Vector2) -> void: ability_input.press(slot, position))
		button.dragged_to.connect(func(position: Vector2) -> void: ability_input.drag(slot, position))
		button.released_at.connect(func(position: Vector2) -> void: ability_input.release(slot, position))
		button.cancelled.connect(ability_input.cancel_aim)
	ability_input.ability_activated.connect(_on_ability_activated)
	_refresh_skill_labels()

func _refresh_skill_labels() -> void:
	for slot in skill_buttons.size():
		var ability := ability_input.ability_definition(slot)
		skill_buttons[slot].setup("" if ability == null else ability.ability_name)

func _on_ability_chosen(ability_id: StringName) -> void:
	_refresh_skill_labels()
	status_label.text = "Slot 1 -> %s" % ability_id

func _on_joystick_vector_changed(vector: Vector2) -> void:
	player.joystick_input = vector
	if vector == Vector2.ZERO:
		status_label.text = HINT
	else:
		status_label.text = "Joystick: (%.2f, %.2f)" % [vector.x, vector.y]

func _on_ability_activated(_slot: int, ability_id: StringName) -> void:
	status_label.text = "Cast: %s" % ability_id

## Spawns another enemy at the next clear spawn point.
func spawn_enemy() -> Enemy:
	var scene := load(ENEMY_SCENE) as PackedScene
	var enemy := scene.instantiate() as Enemy
	add_child(enemy)
	enemy.global_position = SPAWN_POINTS[_spawn_index % SPAWN_POINTS.size()]
	_spawn_index += 1
	status_label.text = "Enemy spawned (%d alive)" % get_tree().get_nodes_in_group(&"enemies").size()
	return enemy
