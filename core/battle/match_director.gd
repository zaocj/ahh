class_name MatchDirector
extends Node
## Owns the shape of a match: READY countdown -> PLAYING -> FINISHED.
##
## Flow
##   READY     the tree is paused (no input, no movement, no shots) while
##             `announce` counts 3 - 2 - 1 - GO
##   PLAYING   `timer_changed` counts the match down; the first side to be wiped
##             loses, and a timeout is decided on remaining health
##   FINISHED  the tree is paused again and `finished` reports the result, which
##             the result overlay shows while offering a rematch
##
## Freezing through `get_tree().paused` is what keeps this node small: it is the
## node that freezes, so it runs with PROCESS_MODE_ALWAYS and everything else
## (player, enemies, projectiles, ability cooldowns, HUD controls) stops on its
## own. That also means READY needs no input-lock code anywhere else.
##
## Win/lose rule for this arena: the player dying loses, wiping every enemy wins,
## both in the same frame is a draw, and the timer compares remaining health
## (player ratio vs. average enemy ratio; a 5% difference is still called a draw).

signal state_changed(state: State)
## Countdown text to show; "" hides it.
signal announce(text: String)
## Match clock as "m:ss".
signal timer_changed(text: String)
signal finished(result: Result, reason: String)

enum State {
	READY,
	PLAYING,
	FINISHED,
}

enum Result {
	NONE,
	PLAYER_WINS,
	ENEMY_WINS,
	DRAW,
}

## Health ratio difference under which a timeout counts as a draw.
const HEALTH_DRAW_MARGIN: float = 0.05

@export_group("Flow")
## Seconds of countdown before the match starts.
@export var ready_seconds: float = 3.0
## Match length in seconds.
@export var match_seconds: float = 60.0
## Start automatically as soon as the scene is ready (tests turn this off to
## configure the flow first, e.g. to use a 1 second match).
@export var auto_start: bool = true
@export_group("Sides")
@export var player_group: StringName = &"players"
@export var enemy_group: StringName = &"enemies"

var state: State = State.READY
var result: Result = Result.NONE
## Human-readable cause of `result` (shown under the result title).
var reason: String = ""

var _time_left: float = 0.0
var _ready_left: float = 0.0
var _announce_left: float = 0.0
var _announce_text: String = ""
var _timer_text: String = ""

func _ready() -> void:
	# The director is the node that pauses and unpauses the tree, so it must keep
	# processing while paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	if auto_start:
		start()

## Begins (or restarts) the match flow: countdown, then the clock runs.
func start() -> void:
	result = Result.NONE
	reason = ""
	_time_left = match_seconds
	_ready_left = ready_seconds
	_timer_text = time_text()
	timer_changed.emit(_timer_text)
	_set_state(State.READY)
	_show_announce(str(int(ceilf(maxf(_ready_left, 1.0)))))
	# No input, no movement, no shooting until GO.
	get_tree().paused = true

## Reloads the arena from scratch. Also clears the pause: the reloaded scene
## starts its own READY, which pauses again by itself.
func restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

## Seconds left on the match clock (never negative).
func time_left() -> float:
	return maxf(_time_left, 0.0)

## Announcement text currently on screen ("" when there is none). Lets the HUD
## paint the right thing even if it connects after `start()` already emitted.
func announce_text() -> String:
	return _announce_text

func time_text() -> String:
	var total := int(ceilf(time_left()))
	return "%d:%02d" % [total / 60, total % 60]

func is_playing() -> bool:
	return state == State.PLAYING

## True while `node` is a valid, living entity (uses the entity `is_alive()`
## convention, falling back to a bare vital component).
func is_alive(node: Node) -> bool:
	if not is_instance_valid(node):
		return false
	if node.has_method("is_alive"):
		return bool(node.call("is_alive"))
	var vitals := node.get_node_or_null("GameplayVitalAttributeComponent") as GameplayVitalAttributeComponent
	return vitals != null and vitals.get_vital_value(&"health") > 0.0

func health_ratio(node: Node) -> float:
	if not is_instance_valid(node):
		return 0.0
	if node.has_method("health_ratio"):
		return float(node.call("health_ratio"))
	var vitals := node.get_node_or_null("GameplayVitalAttributeComponent") as GameplayVitalAttributeComponent
	return 0.0 if vitals == null else vitals.get_vital_percent(&"health")

## Title for the result overlay.
func result_title() -> String:
	match result:
		Result.PLAYER_WINS:
			return "YOU WIN"
		Result.ENEMY_WINS:
			return "YOU LOSE"
		Result.DRAW:
			return "DRAW"
	return ""

## Accent color for the result overlay.
func result_accent() -> Color:
	match result:
		Result.PLAYER_WINS:
			return Color(0.45, 0.95, 0.65)
		Result.ENEMY_WINS:
			return Color(0.95, 0.42, 0.42)
		Result.DRAW:
			return Color(0.85, 0.78, 0.45)
	return Color.WHITE

func _process(delta: float) -> void:
	if _announce_left > 0.0:
		_announce_left -= delta
		if _announce_left <= 0.0:
			_show_announce("")
	match state:
		State.READY:
			_tick_ready(delta)
		State.PLAYING:
			_tick_playing(delta)

func _tick_ready(delta: float) -> void:
	_ready_left -= delta
	if _ready_left > 0.0:
		# Only on change: this runs every frame.
		var text := str(int(ceilf(_ready_left)))
		if text != _announce_text:
			_show_announce(text)
		return
	_show_announce("GO!", 0.8)
	_set_state(State.PLAYING)
	get_tree().paused = false

func _tick_playing(delta: float) -> void:
	_time_left = maxf(_time_left - delta, 0.0)
	if time_text() != _timer_text:
		_timer_text = time_text()
		timer_changed.emit(_timer_text)

	var player := get_tree().get_first_node_in_group(player_group)
	var enemies := _living_enemies()
	var player_alive := is_alive(player)
	if not player_alive and enemies.is_empty():
		_finish(Result.DRAW, "Both sides went down together.")
	elif not player_alive:
		_finish(Result.ENEMY_WINS, "You were defeated.")
	elif enemies.is_empty():
		_finish(Result.PLAYER_WINS, "All enemies destroyed.")
	elif is_zero_approx(_time_left):
		_decide_on_health(player, enemies)

## Timeout: the side with more health left wins; a near tie is a draw.
func _decide_on_health(player: Node, enemies: Array) -> void:
	var mine := health_ratio(player)
	var theirs := 0.0
	for enemy in enemies:
		theirs += health_ratio(enemy)
	theirs /= float(enemies.size())
	var detail := "Time up - health %d%% vs %d%%." % [roundi(mine * 100.0), roundi(theirs * 100.0)]
	if absf(mine - theirs) <= HEALTH_DRAW_MARGIN:
		_finish(Result.DRAW, detail)
	elif mine > theirs:
		_finish(Result.PLAYER_WINS, detail)
	else:
		_finish(Result.ENEMY_WINS, detail)

func _finish(match_result: Result, match_reason: String) -> void:
	result = match_result
	reason = match_reason
	_show_announce("")
	_set_state(State.FINISHED)
	get_tree().paused = true
	finished.emit(result, reason)
	# Report *after* the world froze, so feedback (result sounds, overlay) reacts to
	# a settled state.
	CombatEvents.report_match_finished(result)

func _living_enemies() -> Array[Node]:
	var living: Array[Node] = []
	for node in get_tree().get_nodes_in_group(enemy_group):
		if is_alive(node):
			living.append(node)
	return living

func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(state)

## `hold_seconds` > 0 clears the announcement again after that long.
func _show_announce(text: String, hold_seconds: float = 0.0) -> void:
	_announce_text = text
	_announce_left = hold_seconds
	announce.emit(text)
