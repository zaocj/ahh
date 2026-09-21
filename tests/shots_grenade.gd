extends Node2D
## One-off screenshot run for the grenade: aim (reach ring + blast circle), then the
## blast landing. Writes /tmp/grenade_aim.png and /tmp/grenade_blast.png.
##
## Run windowed (needs a renderer):
##   godot --path . --fixed-fps 60 res://tests/shots_grenade.tscn

const MAIN_SCENE: String = "res://main/main.tscn"

var _main: Node2D = null
var _director: MatchDirector = null
var _player: Unit = null
var _router: AbilityInputRouter = null

func _ready() -> void:
	get_tree().root.size = Vector2i(1152, 648)
	# The pick has to be set before main.tscn spawns its seats.
	MatchConfig.selected_hero = load("res://heroes/bomber/bomber_data.tres")
	await _frames(1)
	_main = (load(MAIN_SCENE) as PackedScene).instantiate() as Node2D
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	await _frames(2)
	_director = _main.get_node("MatchDirector") as MatchDirector
	_player = _main.get_node("Player") as Unit
	_router = _player.get_node("InputRouter") as AbilityInputRouter

	# Skip the countdown and keep the enemy still, so the shot is repeatable.
	_director.match_seconds = 600.0
	_director.start()
	for _i in 8 * 60:
		if _director.is_playing():
			break
		await get_tree().process_frame
	_silence_bots()
	_first_hostile().set_physics_process(false)

	# Slot 0 = the grenade, aimed with a drag towards the enemy.
	# The grenade belongs to the bomber; select it the way the hero screen does.
	MatchConfig.selected_hero = load("res://heroes/bomber/bomber_data.tres")
	var towards := (_first_hostile().global_position - _player.global_position).normalized()
	_router.press(0, Vector2.ZERO)
	for step in 12:
		_router.drag(0, towards * (10.0 + step * 12.0))
		await get_tree().process_frame
	await _frames(3)
	await _save("/tmp/grenade_aim.png")

	_router.release(0, towards * 140.0)
	for _i in 2 * 60:
		if _has_field():
			break
		await get_tree().process_frame
	await _frames(2)
	await _save("/tmp/grenade_blast.png")
	print("shots written")
	get_tree().quit(0)

func _has_field() -> bool:
	for child in _main.get_children():
		if child is MagicField2D:
			return true
	return false

func _save(path: String) -> void:
	# Wait for the frame to be drawn, then read the rendered viewport.
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(path)
	print("wrote ", path)

func _first_hostile() -> Unit:
	return get_tree().get_first_node_in_group(&"team_red") as Unit

func _silence_bots() -> void:
	for unit in get_tree().get_nodes_in_group(&"units"):
		var router := unit.get_node_or_null("AiRouter")
		if router != null:
			router.set_process(false)

func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame
