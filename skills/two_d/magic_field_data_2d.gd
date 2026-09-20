extends Resource
class_name MagicFieldData2D
## Configuration of a 2D magic field (ground zone), mirroring the plugin's
## MagicFieldData - which only ships statuses as a payload and drives a 3D
## MagicFieldBase scene.
##
## Used both for a lasting zone (法阵) and for an instant blast (bomb impact):
## the difference is just duration / radius / payload.

@export_group("Lifetime")
## Seconds the field stays; a short value (0.2) turns it into an explosion.
@export var duration: float = 5.0
## Seconds between payload ticks; <= 0 applies the payload once on spawn.
@export var tick_interval: float = 0.8

@export_group("Shape")
@export var radius: float = 110.0
@export var color: Color = Color(0.55, 0.35, 0.95, 0.28)

@export_group("Targets")
## Group the payload is applied to (the field is cast by the player).
@export var target_group: StringName = &"enemies"

@export_group("Scene")
@export var field_scene: PackedScene
## Effects delivered to every target inside on each tick.
@export var payload_effects: Array[GameplayEffect] = []
