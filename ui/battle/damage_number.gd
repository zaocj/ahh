class_name DamageNumber
extends Node2D
## Floating combat text: rises, fades, frees itself.
##
## Presentation only - it knows nothing about who got hit; `DamageNumbers` spawns
## it from a combat event. Drawn with the fallback font like the rest of the HUD
## Draws with a plain placeholder font (like the rest of the HUD), so no font asset
## is needed yet.

@export var rise_distance: float = 44.0
@export var duration: float = 0.75
@export var font_size: int = 24
## Outline keeps the number readable over walls and floor tiles.
@export var outline_width: int = 4
@export var outline_color: Color = Color(0.04, 0.05, 0.08, 0.9)
## Sidestep range applied by the spawner (kept out of the number itself).
@export var jitter: Vector2 = Vector2(14.0, 6.0)

var _text: String = ""
var _color: Color = Color.WHITE
## Where the number was spawned: the rise is applied on top of this, never instead
## of it (assigning position.y directly would teleport the number to y = 0).
var _origin: Vector2 = Vector2.ZERO
var _elapsed: float = 0.0

func _ready() -> void:
	# Above entities (y-sorted) and above the aim indicator (z_index 100).
	z_index = 200

## `amount` is rounded to whole numbers: the balance numbers are integers.
## `offset` scatters simultaneous hits; the spawn position is taken as the origin.
func setup(amount: float, color: Color, offset: Vector2 = Vector2.ZERO) -> void:
	_color = color
	_text = str(roundi(amount))
	_origin = position + offset
	position = _origin
	queue_redraw()

## The text that gets drawn; lets tests assert what the player actually sees.
func display_text() -> String:
	return _text

func _process(delta: float) -> void:
	_elapsed += delta
	var progress := clampf(_elapsed / maxf(duration, 0.01), 0.0, 1.0)
	position = _origin + Vector2(0.0, -rise_distance * ease(progress, 0.35))
	modulate.a = 1.0 - ease(progress, 1.6)
	if progress >= 1.0:
		queue_free()

func _draw() -> void:
	if _text.is_empty():
		return
	# Centred on the spawn point: the text width depends on the glyphs.
	var width := ThemeDB.fallback_font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string_outline(ThemeDB.fallback_font, Vector2(-width * 0.5, 0.0), _text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline_width, outline_color)
	draw_string(ThemeDB.fallback_font, Vector2(-width * 0.5, 0.0), _text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, _color)
