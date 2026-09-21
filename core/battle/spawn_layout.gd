class_name SpawnLayout
extends Resource
## Where each side starts a match.
##
## Data instead of coordinates in a scene, so a map can bring its own layout and a
## test can assert the points are actually on walkable floor
## (see tests/verify_3v3.gd).

@export var blue_points: Array[Vector2] = []
@export var red_points: Array[Vector2] = []

## Start position for team slot `index`; the last point is reused if a team is
## bigger than the layout (and the arena centre is the final fallback).
func point_for(team: int, index: int) -> Vector2:
	var points := blue_points if team == Teams.Id.BLUE else red_points
	if points.is_empty():
		return Vector2(640.0, 432.0)
	return points[mini(index, points.size() - 1)]
