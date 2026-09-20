extends Node2D
## Arena root: wires the on-screen controls (movement joystick, ability buttons,
## skill drawer) to the player and reports state on the HUD.
##
## Skills are handled by the gameplay ability system plugin; this script only
## routes button presses into it and mirrors cooldowns back onto the buttons.
## Match flow (countdown, clock, win/lose, rematch) belongs to MatchDirector -
## this node just connects it to the HUD labels and the result overlay.
##
## The arena's enemy comes from the scene (position in main.tscn) and a rematch
## reloads it, so nothing here spawns enemies: a wave spawner, when it is needed,
## belongs to core/battle/ next to MatchDirector.

@onready var player: Player = $Player
@onready var joystick: Control = $HUD/Joystick
@onready var status_label: Label = $HUD/Status
@onready var timer_label: Label = $HUD/Timer
@onready var announce_label: Label = $HUD/Announce
@onready var skill_buttons: Array[SkillButton] = [$HUD/SkillBullet, $HUD/SkillDash]
@onready var ability_input: AbilityInputRouter = $Player/InputRouter
@onready var drawer: SkillDrawer = $HUD/SkillDrawer
@onready var drawer_toggle: ActionButton = $HUD/DrawerToggle
@onready var director: MatchDirector = $MatchDirector
@onready var result_overlay: ResultOverlay = $HUD/ResultOverlay
@onready var sfx: CombatSfx = $CombatSfx

## Tag vocabulary the skills use ("status.frozen", ...). The plugin's TagManager
## only knows tags it was handed, and unregistered ones are silently dropped
## (AGENTS.md pitfall 17). Any new entry scene has to register them too.
const TAG_DIRECTORY: String = "res://skills/data/shared/tags/"

## `TagManager.initialize()` is not idempotent: a second call warns ("已经初始化！")
## and re-registering a tag warns too. A rematch reloads this scene, so the
## registration has to happen exactly once per process - hence a static flag
## instead of an instance one.
static var _tags_registered: bool = false

const HINT: String = "WASD / joystick to move | tap a skill to cast, hold to aim | 60s - first one down loses"

func _ready() -> void:
	if not _tags_registered:
		TagManager.initialize(TAG_DIRECTORY)
		_tags_registered = true
	joystick.vector_changed.connect(_on_joystick_vector_changed)
	status_label.text = HINT
	_wire_skill_buttons()
	drawer.setup(ability_input)
	drawer.ability_chosen.connect(_on_ability_chosen)
	drawer_toggle.pressed.connect(drawer.toggle)
	_wire_match_flow()

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

## Match flow wiring: the director decides, the HUD shows, the overlay offers a
## rematch.
func _wire_match_flow() -> void:
	director.timer_changed.connect(func(text: String) -> void: timer_label.text = text)
	director.announce.connect(_on_match_announce)
	director.state_changed.connect(_on_match_state_changed)
	director.finished.connect(_on_match_finished)
	result_overlay.restart_requested.connect(director.restart)
	# The director starts in its own _ready(), which runs before this one, so the
	# first emissions are already gone: paint the current state instead of waiting
	# for the next signal.
	timer_label.text = director.time_text()
	_on_match_announce(director.announce_text())
	_on_match_state_changed(director.state)

func _on_match_state_changed(state: MatchDirector.State) -> void:
	# The help line is for playing; the result overlay speaks for itself.
	status_label.visible = state != MatchDirector.State.FINISHED

func _on_match_announce(text: String) -> void:
	announce_label.text = text
	announce_label.visible = not text.is_empty()
	# Countdown blips are match-flow feedback, not combat events, so they are wired
	# here instead of through CombatEvents.
	sfx.play_announce(text)

func _on_match_finished(result: MatchDirector.Result, reason: String) -> void:
	result_overlay.show_result(director.result_title(), reason, director.result_accent())
