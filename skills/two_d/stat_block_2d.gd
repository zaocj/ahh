extends Resource
class_name StatBlock2D
## Attribute sets + vitals of one entity, bundled for the plugin's
## GameplayVitalAttributeComponent.initialize(sets, vitals).
##
## Same idea as the plugin examples' PlayerData resource: it keeps typed resource
## arrays in a .tres (where they belong) instead of in the scene file.

@export var attribute_sets: Array[GameplayAttributeSet] = []
@export var vitals: Array[GameplayVital] = []
