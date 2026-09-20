extends Node2D
## Arena root: wires the on-screen controls (movement joystick + skill buttons)
## to the player and reports state on the HUD so the input path stays visible.

@onready var player: Player = $Player
@onready var joystick: Control = $HUD/Joystick
@onready var status_label: Label = $HUD/Status
@onready var skill_buttons: Array[SkillButton] = [$HUD/SkillBullet, $HUD/SkillDash]
@onready var skills: SkillController = $Player/Skills

const HINT: String = "WASD / Arrows or drag the joystick to move | tap a skill to cast, hold to aim"

func _ready() -> void:
	joystick.vector_changed.connect(_on_joystick_vector_changed)
	status_label.text = HINT
	_wire_skill_buttons()

## Buttons and skill slots share their order: button i drives slot i.
func _wire_skill_buttons() -> void:
	for slot in skill_buttons.size():
		var button := skill_buttons[slot]
		button.setup(skills.get_skill(slot))
		button.pressed_at.connect(func(position: Vector2) -> void: skills.press(slot, position))
		button.dragged_to.connect(func(position: Vector2) -> void: skills.drag(slot, position))
		button.released_at.connect(func(position: Vector2) -> void: skills.release(slot, position))
		button.cancelled.connect(skills.cancel_aim)
	skills.cooldown_changed.connect(_on_cooldown_changed)
	skills.skill_casted.connect(_on_skill_casted)

func _on_joystick_vector_changed(vector: Vector2) -> void:
	player.joystick_input = vector
	if vector == Vector2.ZERO:
		status_label.text = HINT
	else:
		status_label.text = "Joystick: (%.2f, %.2f)" % [vector.x, vector.y]

func _on_cooldown_changed(slot: int, remaining: float, total: float) -> void:
	if slot < 0 or slot >= skill_buttons.size():
		return
	skill_buttons[slot].set_cooldown_ratio(0.0 if total <= 0.0 else remaining / total)

func _on_skill_casted(_slot: int, skill: SkillData) -> void:
	status_label.text = "Cast: %s" % skill.display_name
