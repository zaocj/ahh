extends Node2D
## Arena root: wires the on-screen controls to the local player's unit and mirrors
## match state onto the HUD.
##
## It no longer owns a player: `MatchDirector` spawns every seat of the 3v3 from the
## roster (the local player is `blue[0]`, or whoever the character select picked),
## so this script only connects what exists after spawning:
##   joystick + skill buttons -> the human unit's AbilityInputRouter
##   director signals         -> timer, score, announce, result overlay
##
## The plugin still owns cooldowns, execution and indicators; this is assembly and
## presentation only.

@onready var joystick: Control = $HUD/Joystick
@onready var status_label: Label = $HUD/Status
@onready var timer_label: Label = $HUD/Timer
@onready var score_label: Label = $HUD/Score
@onready var announce_label: Label = $HUD/Announce
@onready var skill_buttons: Array[SkillButton] = [$HUD/SkillBullet, $HUD/SkillDash]
@onready var director: MatchDirector = $MatchDirector
@onready var camera: UnitCamera = $Camera
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

const HINT: String = "WASD / joystick to move | tap a skill to cast, hold to aim | 3v3: more survivors wins"

var _human_unit: Unit = null
var _ability_input: AbilityInputRouter = null

func _ready() -> void:
	if not _tags_registered:
		TagManager.initialize(TAG_DIRECTORY)
		_tags_registered = true
	joystick.vector_changed.connect(_on_joystick_vector_changed)
	status_label.text = HINT
	# The director cannot add the units while the arena is still building its own
	# children, so it spawns on the next frame and tells us when they are in.
	director.units_ready.connect(_on_units_ready)
	director.spectate_changed.connect(_on_spectate_changed)
	_wire_match_flow()

func _on_units_ready() -> void:
	_bind_human_unit()
	_wire_skill_buttons()
	_check_hero_select()
	camera.setup(director.watched_unit)

## Death of the local player hands the camera to a teammate.
func _on_spectate_changed(unit: Unit) -> void:
	camera.setup(unit)
	status_label.text = "Spectating %s" % unit.display_name()

func _process(_delta: float) -> void:
	if _ability_input == null:
		return
	for slot in skill_buttons.size():
		skill_buttons[slot].set_cooldown_ratio(_ability_input.cooldown_ratio(slot))

## The human unit is the one the director spawned for this player.
func _bind_human_unit() -> void:
	_human_unit = director.human_unit
	if _human_unit == null:
		push_error("main.gd: the match director spawned no human unit.")
		return
	_ability_input = _human_unit.get_node_or_null("InputRouter") as AbilityInputRouter

## Buttons and ability slots share their order: button i drives slot i.
func _wire_skill_buttons() -> void:
	if _ability_input == null:
		return
	for slot in skill_buttons.size():
		var button := skill_buttons[slot]
		button.pressed_at.connect(func(position: Vector2) -> void: _ability_input.press(slot, position))
		button.dragged_to.connect(func(position: Vector2) -> void: _ability_input.drag(slot, position))
		button.released_at.connect(func(position: Vector2) -> void: _ability_input.release(slot, position))
		button.cancelled.connect(_ability_input.cancel_aim)
	_ability_input.ability_activated.connect(_on_ability_activated)
	_refresh_skill_labels()

func _refresh_skill_labels() -> void:
	for slot in skill_buttons.size():
		var ability := _ability_input.ability_definition(slot)
		skill_buttons[slot].setup("" if ability == null else ability.ability_name)

## Match flow wiring: the director decides, the HUD shows, the overlay offers a rematch.
func _wire_match_flow() -> void:
	director.timer_changed.connect(func(text: String) -> void: timer_label.text = text)
	director.score_changed.connect(_on_score_changed)
	director.announce.connect(_on_match_announce)
	director.state_changed.connect(_on_match_state_changed)
	director.finished.connect(_on_match_finished)
	result_overlay.restart_requested.connect(director.restart)
	# The director starts in its own _ready(), which runs before this one, so the
	# first emissions are already gone: paint the current state instead of waiting
	# for the next signal.
	timer_label.text = director.time_text()
	_on_score_changed(director.living(Teams.Id.BLUE), director.living(Teams.Id.RED))
	_on_match_announce(director.announce_text())
	_on_match_state_changed(director.state)

## "3 : 2" for the two teams, with an overtime marker on the clock.
func _on_score_changed(blue: int, red: int) -> void:
	score_label.text = "%d : %d" % [blue, red]

func _on_match_state_changed(state: MatchDirector.State) -> void:
	# The help line is for playing; the result overlay speaks for itself.
	status_label.visible = state != MatchDirector.State.FINISHED

func _on_match_announce(text: String) -> void:
	announce_label.text = text
	announce_label.visible = not text.is_empty()
	# Countdown / overtime blips are match-flow feedback, not combat events, so they
	# are wired here instead of through CombatEvents.
	sfx.play_announce(text)

func _on_match_finished(result: MatchDirector.Result, reason: String) -> void:
	result_overlay.show_result(director.result_title(), reason, director.result_accent(),
		director.stats.rows())

func _on_ability_activated(_slot: int, ability_id: StringName) -> void:
	status_label.text = "Cast: %s" % ability_id

func _on_joystick_vector_changed(vector: Vector2) -> void:
	if _human_unit != null:
		_human_unit.joystick_input = vector
	if vector == Vector2.ZERO:
		status_label.text = HINT
	else:
		status_label.text = "Joystick: (%.2f, %.2f)" % [vector.x, vector.y]

## Played straight from the lobby without a hero pick: fall back to the roster's
## first blue seat (tests rely on that, and so does a quick F5).
func _check_hero_select() -> void:
	if _human_unit != null and _human_unit.hero != null:
		status_label.text = "%s - %s" % [_human_unit.hero.display_name, HINT]
