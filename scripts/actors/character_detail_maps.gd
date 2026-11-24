class_name CharacterDetailMaps
extends Resource
## The local maps one material of a `CharacterLook` draws on a part that carries UVs.
##
## The GLBs the game ships were authored without UVs, so every character's paint is placed by
## position. The protagonist's V2 head is the first part that carries its own UV atlas
## (`tools/head_v2.py`), and on it the fine relief and the local colour go into maps instead of
## into more triangles: the albedo map carries the lips, the bruise and the stubble, the normal
## map carries the brow ridge, the nasolabial and mental creases, the eyelid crease and the
## skin grain — detail a 22k-triangle head cannot hold. Both are optional and per material.
##
## `CharacterLookApplier` sets them on the surface only when that surface really has UVs, and
## only while its `detail_maps_enabled` is on, which is the A/B the issue asks for: with the
## switch off, the same look draws the same flat colour it drew before.

## The part's colour map, a multiplier over the look's own albedo and pigment.
@export var albedo: Texture2D = null
## How much of the map's colour to draw (1 = all of it).
@export var albedo_mix: float = 1.0
## The part's tangent-space normal map, OpenGL (+Y) convention as Godot expects.
@export var normal: Texture2D = null
## Normal-map depth, as Godot's `NORMAL_MAP_DEPTH`.
@export var normal_strength: float = 1.0


func has_any() -> bool:
	return albedo != null or normal != null
