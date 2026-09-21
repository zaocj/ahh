extends Node2D
## One-off screenshot run for the end screen: plays a short 3v3 to its result and
## writes /tmp/result.png (title, cause and the hero / kills / damage scoreboard).
##
## Run windowed (needs a renderer):
##   godot --path . --fixed-fps 60 res://tests/shots_result.tscn

const MAIN_SCENE: String = "res://main/main.tscn"
const DAMAGE: String = "res://skills/data/shared/effects/bullet_damage.tres"

var _main: Node2D = null
var _director: MatchDirector = null

func _ready() -> void:
	get_tree().root.size = Vector2i(1152, 648)
	# Pick the bomber the way the character select screen does.
	MatchConfig.selected_hero = load("res://heroes/bomber/bomber_data.tres")
	await _frames(1)
	_main = (load(MAIN_SCENE) as PackedScene).instantiate() as Node2D
	get_tree().root.add_child(_main)
	get_tree().current_scene = _main
	await _frames(3)
	_director = _main.get_node("MatchDirector") as MatchDirector
	for _i in 8 * 60:
		if _director.is_playing():
			break
		await get_tree().process_frame

	# Spread some damage around so the scoreboard is not a row of zeros, then end the
	# match by wiping the red team.
	var damage := load(DAMAGE) as GameplayEffect
	var human := _director.human_unit
	var blues := get_tree().get_nodes_in_group(Teams.group_of(Teams.Id.BLUE))
	var reds := get_tree().get_nodes_in_group(Teams.group_of(Teams.Id.RED))
	# 10 damage a bullet: spread a little for the scoreboard, then finish them.
	for i in reds.size():
		var red: Unit = reds[i]
		var shooter: Unit = blues[i % blues.size()]
		for _hit in 1 + i:
			(damage.duplicate(true) as GameplayEffect).apply(red, shooter, {})
		await _frames(2)
	for red in reds:
		for _hit in 12:
			(damage.duplicate(true) as GameplayEffect).apply(red, human, {})
	await _frames(4)
	await _save("/tmp/result.png")
	print("result: %s / %s" % [_director.result_title(), _director.reason])
	get_tree().quit(0)

func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("wrote ", path)

func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame
