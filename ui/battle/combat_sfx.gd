class_name CombatSfx
extends Node
## Placeholder combat audio: a small pool of players, streams wired in the scene.
##
## One subscriber for the whole match, so no gameplay code ever plays a sound
## itself. The streams under `assets/audio/` are synthesised placeholders (short
## envelopes over a sine/noise source), meant to be replaced by real audio - swap
## the file and the wiring stays.
##
## The voice pool is built in code on purpose: its size is a tuning value, not
## authored content, and `play()` has to pick a free voice at runtime anyway.

@export_group("Streams")
@export var player_hit_stream: AudioStream
@export var hit_stream: AudioStream
@export var shoot_stream: AudioStream
@export var dash_stream: AudioStream
@export var death_stream: AudioStream
@export var win_stream: AudioStream
@export var lose_stream: AudioStream
@export var draw_stream: AudioStream
@export var tick_stream: AudioStream

@export_group("Mix")
## Simultaneous sounds; beyond this the oldest voice is reused.
@export var voices: int = 6
@export var volume_db: float = -6.0
## Pitch wobble in semitone-ish fractions, so repeated hits do not sound robotic.
@export var pitch_jitter: float = 0.07
## Enemy casts are pitched down a little, to tell the two sides apart by ear.
@export var enemy_pitch: float = 0.82

var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var _rng := RandomNumberGenerator.new()
## Stream handed to a voice by the last `play()`; debugging and tests use it to
## prove what the game asked for even when the driver is a dummy (--headless).
var _last_stream: AudioStream = null
## Recently requested streams, newest last. `playing` is not a reliable witness:
## a short sound can be over before the next frame (and headless has no real audio
## clock at all), so "was this sound asked for" needs its own record.
var _history: Array[AudioStream] = []

const HISTORY_LIMIT: int = 12

func _ready() -> void:
	_rng.randomize()
	for i in voices:
		var player := AudioStreamPlayer.new()
		player.volume_db = volume_db
		add_child(player)
		_players.append(player)
	CombatEvents.damaged.connect(_on_damaged)
	CombatEvents.died.connect(_on_died)
	CombatEvents.ability_cast.connect(_on_ability_cast)
	CombatEvents.match_finished.connect(_on_match_finished)

## Plays a one-shot on the next free voice (round robin).
func play(stream: AudioStream, pitch: float = 1.0, volume_offset_db: float = 0.0) -> void:
	if stream == null or _players.is_empty():
		return
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = stream
	player.pitch_scale = maxf(pitch, 0.05)
	player.volume_db = volume_db + volume_offset_db
	player.play()
	_last_stream = stream
	_history.append(stream)
	while _history.size() > HISTORY_LIMIT:
		_history.pop_front()

## Stream of the most recent `play()` call.
func last_stream() -> AudioStream:
	return _last_stream

## Streams requested recently (newest last); for debugging and assertions.
func play_history() -> Array[AudioStream]:
	return _history

## Streams currently playing (for debugging and assertions).
func playing_streams() -> Array[AudioStream]:
	var streams: Array[AudioStream] = []
	for player in _players:
		if player.playing and player.stream != null:
			streams.append(player.stream)
	return streams

## Countdown blip / "GO!" - driven by main.gd from the match director, since it is
## match-flow feedback rather than a combat event.
func play_announce(text: String) -> void:
	if text.is_empty():
		return
	play(tick_stream, 1.25 if text == "GO!" else 1.0)

func _on_damaged(victim: Node2D, _amount: float, _source: Node) -> void:
	if victim == null:
		return
	if victim.is_in_group(&"players"):
		# Louder and lower: the player must hear that they are the one being hit.
		play(player_hit_stream, 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter), 3.0)
	else:
		play(hit_stream, 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter))

func _on_died(_entity: Node2D, _source: Node) -> void:
	play(death_stream)

func _on_ability_cast(caster: Node2D, ability_id: StringName) -> void:
	var is_enemy := caster != null and caster.is_in_group(&"enemies")
	var pitch := enemy_pitch if is_enemy else 1.0
	if ability_id == &"dash":
		play(dash_stream, pitch)
	else:
		play(shoot_stream, pitch)

func _on_match_finished(result: int) -> void:
	match result:
		1:  # MatchDirector.Result.PLAYER_WINS
			play(win_stream, 1.0, 2.0)
		2:  # ENEMY_WINS
			play(lose_stream, 1.0, 2.0)
		_:
			play(draw_stream, 1.0, 2.0)
