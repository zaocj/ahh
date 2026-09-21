class_name MatchConfig
extends RefCounted
## What the character select screen hands to the match scene.
##
## A static holder instead of an autoload: the lobby is a separate scene, so the pick
## has to survive `change_scene_to_file()`, and a static variable is the smallest
## thing that does that. Tests set it (or leave it null to use the roster default).

static var selected_hero: HeroData = null

static func clear() -> void:
	selected_hero = null
