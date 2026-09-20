class_name SkillIndicatorData
extends Resource
## Visual parameters of a skill's aiming indicator.
##
## Every skill owns one of these; SkillIndicator itself stays generic and only
## reads this resource.

enum Shape {
	LINE, ## Straight line from the caster, worth `length` pixels.
	ARROW, ## Line ending in an arrow head (the Brawl-Stars style aim).
	CIRCLE, ## Circle centred on the caster, used by range/AoE skills.
}

@export var shape: Shape = Shape.ARROW
## LINE/ARROW: how far the indicator reaches. CIRCLE: its radius.
@export var length: float = 260.0
## LINE/ARROW: shaft thickness. Ignored by CIRCLE.
@export var width: float = 14.0
## Length of the arrow head. Ignored unless shape is ARROW.
@export var head_length: float = 52.0
@export var fill_color: Color = Color(0.24, 0.78, 0.94, 0.22)
@export var outline_color: Color = Color(0.24, 0.78, 0.94, 0.9)
@export var outline_width: float = 2.0
