extends Node2D
## Arena root: wires the on-screen controls (movement joystick + ability buttons)
## to the player and reports state on the HUD so the input path stays visible.
##
## Skills are handled by the gameplay ability system plugin; this script only
## routes button presses into it and mirrors cooldowns back onto the buttons.

@onready var player: Player = $Player
@onready var joystick: Control = $HUD/Joystick
@onready var status_label: Label = $HUD/Status
@onready var skill_buttons: Array[SkillButton] = [$HUD/SkillBullet, $HUD/SkillDash]
@onready var ability_input: AbilityInputRouter = $Player/InputRouter

const HINT: String = "WASD / Arrows or drag the joystick to move | tap a skill to cast, hold to aim"

func _ready() -> void:
	joystick.vector_changed.connect(_on_joystick_vector_changed)
	status_label.text = HINT
	_wire_skill_buttons()

func _process(_delta: float) -> void:
	for slot in skill_buttons.size():
		skill_buttons[slot].set_cooldown_ratio(ability_input.cooldown_ratio(slot))

## Buttons and ability slots share their order: button i drives slot i.
func _wire_skill_buttons() -> void:
	for slot in skill_buttons.size():
		var button := skill_buttons[slot]
		var ability := ability_input.ability_definition(slot)
		if ability != null:
			button.setup(ability.ability_name)
		button.pressed_at.connect(func(position: Vector2) -> void: ability_input.press(slot, position))
		button.dragged_to.connect(func(position: Vector2) -> void: ability_input.drag(slot, position))
		button.released_at.connect(func(position: Vector2) -> void: ability_input.release(slot, position))
		button.cancelled.connect(ability_input.cancel_aim)
	ability_input.ability_activated.connect(_on_ability_activated)

func _on_joystick_vector_changed(vector: Vector2) -> void:
	player.joystick_input = vector
	if vector == Vector2.ZERO:
		status_label.text = HINT
	else:
		status_label.text = "Joystick: (%.2f, %.2f)" % [vector.x, vector.y]

func _on_ability_activated(_slot: int, ability_id: StringName) -> void:
	status_label.text = "Cast: %s" % ability_id
