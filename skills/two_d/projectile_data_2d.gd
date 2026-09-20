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

@export_group("Scene")
## The 2D projectile scene (must expose launch(direction, speed, max_distance)).
@export var projectile_scene: PackedScene

@export_group("Payload")
## Effects applied to whatever the projectile hits (GE_ApplyDamage, statuses, ...).
@export var payload_effects: Array[GameplayEffect] = []
