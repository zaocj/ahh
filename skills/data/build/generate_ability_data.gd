extends Node
## One-off authoring scene for the ability data of this project.
##
## The plugin's abilities are nested resources (features + preview strategy +
## behavior tree), so they are generated here instead of being hand-written.
## Run:  godot --headless --path . res://skills/data/build/generate_ability_data.tscn
##
## It must run as a *scene* (not --script): the plugin's scripts use its autoload
## singletons as global identifiers, which only resolve in a normal project run.
##
## After the first run the .tres files are normal project resources: edit them in
## the editor. Re-running this scene overwrites them.

const ROOT := "res://skills/data/"
const PROJECTILE_SCENE := "res://entities/projectile/projectile.tscn"
const PLAYER_ATTRIBUTE_SET := ROOT + "shared/attributes/player_attributes.tres"
const PLAYER_VITAL_HEALTH := ROOT + "shared/vitals/health.tres"

func _ready() -> void:
	_generate_shared()
	_generate_shot()
	_generate_dash()
	_generate_loadout()
	print("generate_ability_data: done")
	get_tree().quit(0)

#region ========== shared attributes / vitals / effects ==========
func _generate_shared() -> void:
	# --- attributes: what the health vital uses as its maximum ---
	var max_health := GameplayAttribute.new()
	max_health.attribute_id = &"max_health"
	max_health.attribute_display_name = "Max Health"
	max_health.min_value = 0.0
	_save(max_health, ROOT + "shared/attributes/max_health.tres")

	var attack := GameplayAttribute.new()
	attack.attribute_id = &"attack"
	attack.attribute_display_name = "Attack"
	attack.min_value = 0.0
	_save(attack, ROOT + "shared/attributes/attack.tres")

	var defense := GameplayAttribute.new()
	defense.attribute_id = &"defense"
	defense.attribute_display_name = "Defense"
	defense.min_value = 0.0
	_save(defense, ROOT + "shared/attributes/defense.tres")

	# --- attribute set: 100 max health, used by the enemy ---
	var enemy_attributes := GameplayAttributeSet.new()
	enemy_attributes.attributes = {max_health: 100.0}
	_save(enemy_attributes, ROOT + "shared/attributes/enemy_attributes.tres")

	var player_attributes := GameplayAttributeSet.new()
	player_attributes.attributes = {max_health: 100.0}
	_save(player_attributes, PLAYER_ATTRIBUTE_SET)

	# --- health vital ---
	var health := HealthVital.new()
	health.vital_id = &"health"
	health.display_name = "Health"
	health.max_value_attribute = &"max_health"
	_save(health, PLAYER_VITAL_HEALTH)

	# --- flat 10 damage, used as the bullet payload ---
	var flat_damage := FlatDamageLogic.new()
	flat_damage.damage_amount = 10.0
	_save(flat_damage, ROOT + "shared/effects/flat_damage_10.tres")

	var bullet_damage := GE_ApplyDamage.new()
	bullet_damage.damage_strategy = flat_damage
	bullet_damage.vital_id = &"health"
	_save(bullet_damage, ROOT + "shared/effects/bullet_damage.tres")

	# --- stat block: what the plugin's vitals component gets on an entity ---
	var stats := StatBlock2D.new()
	var stat_sets: Array[GameplayAttributeSet] = [enemy_attributes]
	var stat_vitals: Array[GameplayVital] = [health]
	stats.attribute_sets = stat_sets
	stats.vitals = stat_vitals
	_save(stats, ROOT + "shared/vitals/enemy_stats.tres")
#endregion

#region ========== skill 1: shot ==========
func _generate_shot() -> void:
	var indicator := SkillIndicatorData.new()
	indicator.shape = SkillIndicatorData.Shape.ARROW
	indicator.length = 480.0
	indicator.width = 14.0
	indicator.head_length = 56.0
	indicator.fill_color = Color(0.98, 0.72, 0.25, 0.2)
	indicator.outline_color = Color(1.0, 0.85, 0.45, 0.9)
	_save(indicator, ROOT + "player/shot/indicator.tres")

	var preview := IndicatorPreview2D.new()
	preview.indicator_data = indicator
	preview.default_aim = IndicatorPreview2D.DefaultAim.TO_TARGET
	preview.target_group = &"enemies"
	preview.max_range = 480.0
	_save(preview, ROOT + "player/shot/preview.tres")

	var bullet := ProjectileData2D.new()
	bullet.speed = 520.0
	bullet.max_distance = 480.0
	bullet.projectile_scene = load(PROJECTILE_SCENE)
	var payload: Array[GameplayEffect] = [load(ROOT + "shared/effects/bullet_damage.tres")]
	bullet.payload_effects = payload
	_save(bullet, ROOT + "player/shot/bullet.tres")

	var cooldown := CooldownFeature.new()
	cooldown.cooldown_duration = 1.0

	var spawn := AbilityNodeSpawnProjectile2D.new()
	spawn.node_id = &"spawn_projectile"
	spawn.projectile_data = bullet
	spawn.direction_key = "target_direction"

	var commit := AbilityNodeCommitCooldown.new()
	commit.node_id = &"commit_cooldown"

	var tree := GAS_BTSequence.new()
	tree.node_id = &"shot_sequence"
	var children: Array[GAS_BTNode] = [commit, spawn]
	tree.children = children

	var ability := GameplayAbilityDefinition.new()
	ability.ability_id = &"shot"
	ability.ability_name = "Shot"
	ability.description = "Fires a bullet straight ahead; tap auto-aims at the nearest enemy."
	ability.preview_strategy = preview
	var shot_features: Array[GameplayAbilityFeature] = [cooldown]
	ability.features = shot_features
	ability.execution_tree = tree
	_save(ability, ROOT + "player/shot/shot.tres")
#endregion

#region ========== skill 2: dash ==========
func _generate_dash() -> void:
	var indicator := SkillIndicatorData.new()
	indicator.shape = SkillIndicatorData.Shape.ARROW
	indicator.length = 168.0
	indicator.width = 8.0
	indicator.head_length = 34.0
	indicator.fill_color = Color(0.42, 0.86, 0.55, 0.2)
	indicator.outline_color = Color(0.55, 0.95, 0.68, 0.9)
	_save(indicator, ROOT + "player/dash/indicator.tres")

	var preview := IndicatorPreview2D.new()
	preview.indicator_data = indicator
	preview.default_aim = IndicatorPreview2D.DefaultAim.AWAY_FROM_TARGET
	preview.target_group = &"enemies"
	preview.max_range = 168.0
	_save(preview, ROOT + "player/dash/preview.tres")

	var cooldown := CooldownFeature.new()
	cooldown.cooldown_duration = 2.0

	var move := GE_Dash2D.new()
	move.distance = 168.0
	move.duration = 0.16

	var self_target := SelfTargetingStrategy.new()
	var search := AbilityNodeTargetSearch.new()
	search.node_id = &"self_target"
	search.strategy = self_target
	search.write_to_key = "targets"
	search.fail_if_empty = true

	var apply := AbilityNodeApplyEffect.new()
	apply.node_id = &"apply_dash"
	var move_effects: Array[GameplayEffect] = [move]
	apply.effects = move_effects
	apply.target_key = "targets"

	var commit := AbilityNodeCommitCooldown.new()
	commit.node_id = &"commit_cooldown"

	var tree := GAS_BTSequence.new()
	tree.node_id = &"dash_sequence"
	var children: Array[GAS_BTNode] = [commit, search, apply]
	tree.children = children

	var ability := GameplayAbilityDefinition.new()
	ability.ability_id = &"dash"
	ability.ability_name = "Dash"
	ability.description = "Short dash towards the aim; tap dashes away from the nearest enemy."
	ability.preview_strategy = preview
	var shot_features: Array[GameplayAbilityFeature] = [cooldown]
	ability.features = shot_features
	ability.execution_tree = tree
	_save(ability, ROOT + "player/dash/dash.tres")
#endregion

#region ========== player loadout (which skills, in HUD slot order) ==========
func _generate_loadout() -> void:
	var shot := load(ROOT + "player/shot/shot.tres") as GameplayAbilityDefinition
	var dash := load(ROOT + "player/dash/dash.tres") as GameplayAbilityDefinition
	var loadout := AbilityLoadout2D.new()
	var list: Array[GameplayAbilityDefinition] = [shot, dash]
	loadout.abilities = list
	_save(loadout, ROOT + "player/loadout.tres")
#endregion

func _save(resource: Resource, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error := ResourceSaver.save(resource, path)
	if error != OK:
		push_error("Failed to save %s (%d)" % [path, error])
	else:
		print("  wrote ", path)
