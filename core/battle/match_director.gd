class_name MatchDirector
extends Node
## Owns the shape of a 3v3 match: spawn -> READY countdown -> PLAYING -> OVERTIME
## -> FINISHED, plus who won, the clock and the scoreboard.
##
## Rules of the mode:
##   - two teams of three, **no respawns**: a defeated unit stays defeated
##   - one minute; at the end the team with more units standing wins
##   - equal survivors -> 30s overtime, where the first side to lose a unit loses
##   - still equal when overtime ends -> draw
##   - wiping a team ends the match immediately, whenever that happens
##
## Freezing: the tree is paused during READY and FINISHED. This node is the one that
## pauses, so it runs PROCESS_MODE_ALWAYS and everything else (units, projectiles,
## cooldowns, HUD controls) stops by itself - READY needs no input locking anywhere.
##
## It also owns the scoreboard (`MatchStats`, fed by CombatEvents) and the simple
## spectating rule: when the local player's unit dies, the camera jumps to a living
## teammate instead of staring at a corpse for a minute.

signal state_changed(state: State)
## Countdown / overtime text to show; "" hides it.
signal announce(text: String)
## Match clock as "m:ss".
signal timer_changed(text: String)
## Living units per team, in the order (blue, red).
signal score_changed(blue: int, red: int)
signal finished(result: Result, reason: String)
## Every seat is spawned and in the tree; the HUD/camera wiring happens then.
signal units_ready
## The camera should watch this unit (the local player, or the teammate being
## spectated after a death). The director owns the rule; main.gd owns the camera.
signal spectate_changed(unit: Unit)

enum State {
	READY,
	PLAYING,
	FINISHED,
}

enum Result {
	NONE,
	BLUE_WINS,
	RED_WINS,
	DRAW,
}

@export_group("Match")
## Who plays: blue[0] is the local player's seat unless a hero was picked.
@export var roster: TeamRoster
## Where each side starts (data, generated from the arena map).
@export var spawns: SpawnLayout
## One combat unit; every seat instantiates it.
@export var unit_scene: PackedScene
## Side the local player fights for.
@export var human_team: int = Teams.Id.BLUE
@export var ready_seconds: float = 3.0
@export var match_seconds: float = 60.0
## Extra time when the survivor counts are level at the end of the clock.
@export var overtime_seconds: float = 30.0
## Start automatically when the scene is ready (tests configure the flow first).
@export var auto_start: bool = true

var state: State = State.READY
var result: Result = Result.NONE
## Human-readable cause of `result`.
var reason: String = ""
## Units of both teams, in spawn order.
var units: Array[Unit] = []
## The unit the skill buttons belong to (the local player's seat).
var human_unit: Unit = null
## The unit the camera watches: the local player while alive, else a teammate.
var watched_unit: Unit = null
## Kills / damage per unit; the end screen reads this.
var stats: MatchStats = null

var _time_left: float = 0.0
var _ready_left: float = 0.0
var _announce_left: float = 0.0
var _announce_text: String = ""
var _timer_text: String = ""
var _overtime: bool = false
var _blue_alive: int = 0
var _red_alive: int = 0
var _spawned: bool = false

func _ready() -> void:
	# The director is the node that pauses and unpauses the tree, so it must keep
	# processing while paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	stats = MatchStats.new()
	stats.name = "MatchStats"
	add_child(stats)
	# Units live next to the arena, and a child may not add nodes to a parent that is
	# still setting up its own children ("Parent node is busy setting up children").
	# Spawning and starting therefore happen on the next frame, after `units_ready`
	# gives the HUD a chance to bind to the local player's unit.
	_spawn_and_start.call_deferred()

func _spawn_and_start() -> void:
	_spawn_units()
	units_ready.emit()
	if auto_start:
		start()

## Begins (or restarts) the flow: countdown, then the clock runs.
func start() -> void:
	if not _spawned:
		_spawn_units()
	result = Result.NONE
	reason = ""
	_overtime = false
	_time_left = match_seconds
	_ready_left = ready_seconds
	_timer_text = time_text()
	timer_changed.emit(_timer_text)
	_set_state(State.READY)
	_show_announce(str(int(ceilf(maxf(_ready_left, 1.0)))))
	# No input, no movement, no shooting until GO.
	get_tree().paused = true

## Reloads the arena from scratch (a rematch also respawns everyone).
func restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

## Seconds left on the clock (never negative).
func time_left() -> float:
	return maxf(_time_left, 0.0)

func time_text() -> String:
	var total := int(ceilf(time_left()))
	return "%d:%02d" % [total / 60, total % 60]

func is_playing() -> bool:
	return state == State.PLAYING

func is_overtime() -> bool:
	return _overtime

## Living units of a team; the whole match is decided by these two numbers.
func living(team: int) -> int:
	var count := 0
	for unit in units:
		if is_instance_valid(unit) and unit.team == team and unit.is_alive():
			count += 1
	return count

## Did the local player's side win?
func player_won() -> bool:
	match result:
		Result.BLUE_WINS:
			return human_team == Teams.Id.BLUE
		Result.RED_WINS:
			return human_team == Teams.Id.RED
	return false

## Title for the result overlay, from the local player's point of view.
func result_title() -> String:
	match result:
		Result.NONE:
			return ""
		Result.DRAW:
			return "DRAW"
	return "YOU WIN" if player_won() else "YOU LOSE"

func result_accent() -> Color:
	match result:
		Result.BLUE_WINS:
			return Teams.color_of(Teams.Id.BLUE)
		Result.RED_WINS:
			return Teams.color_of(Teams.Id.RED)
		Result.DRAW:
			return Color(0.85, 0.78, 0.45)
	return Color.WHITE

## Announcement text currently on screen ("" when there is none).
func announce_text() -> String:
	return _announce_text

#region ========== spawning ==========
func _spawn_units() -> void:
	if _spawned or unit_scene == null or roster == null:
		return
	_spawned = true
	# The character select screen stores its pick here; without one the first blue
	# roster seat is the local player (what every test relies on).
	var picked := MatchConfig.selected_hero

	for team in [Teams.Id.BLUE, Teams.Id.RED]:
		var lineup := roster.lineup_for(team, picked if team == human_team else null)
		for index in lineup.size():
			var hero := lineup[index]
			if not is_instance_valid(hero):
				continue
			_spawn_unit(hero, team, index)

	_blue_alive = living(Teams.Id.BLUE)
	_red_alive = living(Teams.Id.RED)
	score_changed.emit(_blue_alive, _red_alive)

func _spawn_unit(hero: HeroData, team: int, index: int) -> void:
	var unit := unit_scene.instantiate() as Unit
	if unit == null:
		push_error("MatchDirector: unit_scene is not a Unit scene.")
		return
	var is_human := team == human_team and index == 0
	unit.name = "Player" if is_human else "%sBot%d" % [Teams.display_name(team), index]
	unit.configure(hero, team, Unit.Controller.HUMAN if is_human else Unit.Controller.AI)
	# Spawned next to the arena (not under the director) so y-sorting and the
	# camera limits work like any other world entity.
	get_parent().add_child(unit)
	if spawns != null:
		unit.global_position = spawns.point_for(team, index)
	# The signal carries no argument: bind the unit so the handler knows who fell.
	unit.died.connect(_on_unit_died.bind(unit))
	_add_brain(unit, hero, is_human)
	stats.register(unit, hero, team, is_human)
	units.append(unit)
	if is_human:
		human_unit = unit
		watched_unit = unit

## Human seats get button input, AI seats get the ability router and a chase brain
## (that lives in the unit itself, driven by its `controller`).
func _add_brain(unit: Unit, hero: HeroData, is_human: bool) -> void:
	if is_human:
		var router := AbilityInputRouter.new()
		router.name = "InputRouter"
		router.loadout = hero.loadout
		unit.add_child(router)
	else:
		var ai := AiAbilityRouter.new()
		ai.name = "AiRouter"
		ai.loadout = hero.loadout
		unit.add_child(ai)
#endregion

#region ========== flow ==========
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

	var blue := living(Teams.Id.BLUE)
	var red := living(Teams.Id.RED)
	if blue != _blue_alive or red != _red_alive:
		_blue_alive = blue
		_red_alive = red
		score_changed.emit(blue, red)

	# A wipe decides it at any time, overtime included.
	if blue == 0 or red == 0:
		if blue == 0 and red == 0:
			_finish(Result.DRAW, "Both teams were wiped out.")
		elif blue == 0:
			_finish(Result.RED_WINS, "Blue team was wiped out.")
		else:
			_finish(Result.BLUE_WINS, "Red team was wiped out.")
		return

	if _overtime:
		# Overtime: the first side to lose a unit loses the match.
		if blue != red:
			_decide_by_survivors(blue, red, "Overtime: ")
		elif is_zero_approx(_time_left):
			_finish(Result.DRAW, "Overtime ended level at %d-%d." % [blue, red])
		return

	if not is_zero_approx(_time_left):
		return
	if blue == red:
		_start_overtime(blue, red)
	else:
		_decide_by_survivors(blue, red, "Time up: ")

func _start_overtime(blue: int, red: int) -> void:
	_overtime = true
	_time_left = overtime_seconds
	_show_announce("+%ds OVERTIME" % int(overtime_seconds), 2.0)
	timer_changed.emit(time_text())
	score_changed.emit(blue, red)

func _decide_by_survivors(blue: int, red: int, prefix: String) -> void:
	var detail := "%s%d survivors vs %d." % [prefix, blue, red]
	if blue > red:
		_finish(Result.BLUE_WINS, detail)
	else:
		_finish(Result.RED_WINS, detail)

func _finish(match_result: Result, match_reason: String) -> void:
	result = match_result
	reason = match_reason
	_show_announce("")
	_set_state(State.FINISHED)
	get_tree().paused = true
	finished.emit(result, reason)
	# Reported after the world froze, so feedback reacts to a settled state.
	CombatEvents.report_match_finished(result)

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
#endregion

#region ========== spectating ==========
## When the local player's unit dies the camera moves to a living teammate, so a
## 3v3 does not turn into a minute of watching a grey square.
func _on_unit_died(unit: Unit) -> void:
	if unit != watched_unit:
		return
	var next := _first_living(human_team)
	if next == null:
		return
	watched_unit = next
	spectate_changed.emit(next)

func _first_living(team: int) -> Unit:
	for unit in units:
		if is_instance_valid(unit) and unit.team == team and unit.is_alive():
			return unit
	return null
#endregion
