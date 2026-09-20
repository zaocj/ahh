extends Resource
class_name ProjectileData2D
## Configuration of a 2D projectile, mirroring the plugin's ProjectileData (which
## is 3D only: it drives a ProjectileBase/CharacterBody3D scene).
##
## Holds everything the fired projectile needs: how it flies, where it lives and
## which plugin effects it delivers on impact.

@export_group("Movement")
@export var speed: float = 520.0
## Flies this far, then despawns; keep it equal to the skill's indicator length.
@export var max_distance: float = 480.0

@export_group("Flight")
## Lobbed shots sail over everything and detonate at the end of their range, like a
## thrown grenade: they must not be stopped by the first body or wall they brush.
@export var lob: bool = false
## Visual arc height of a lob; the collision stays on the straight line so the
## landing point is exactly where the player aimed.
@export var lob_height: float = 30.0
## Tumble speed for a lobbed projectile, in radians per second.
@export var spin_speed: float = 14.0

@export_group("Scene")
## The 2D projectile scene (must expose launch(direction, speed, max_distance)).
@export var projectile_scene: PackedScene

@export_group("Payload")
## Effects applied to whatever the projectile hits (GE_ApplyDamage, statuses, ...).
@export var payload_effects: Array[GameplayEffect] = []
## Field dropped at the impact point / end of flight: this is how the bomb
## explodes (the same MagicField2D used for a lasting sigil, only shorter).
@export var impact_field: MagicFieldData2D = null

@export_group("Targets")
## Group this projectile may damage; empty = anything damageable. Enemy bolts use
## `players` so they pass through other enemies instead of friendly-firing them.
@export var target_group: StringName = &""
