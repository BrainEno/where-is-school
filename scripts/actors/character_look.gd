class_name CharacterLook
extends Resource
## What one character looks like in the game, on top of the GLB it was modelled in.
##
## The GLBs keep their own flat-colour materials (the protagonist's twelve, Q's fourteen):
## they are the owner's export and every import test reads them. A look replaces them *at
## runtime*, per surface, by material name, with painted materials
## (`assets/shaders/characters/character_paint.gdshader`, plus the ink hull
## `character_outline.gdshader` as `next_pass` on the parts that carry a line), and sets
## the face's resting expression on the model's own blend shapes. `CharacterLookApplier`
## does the applying; `art/characters/build_character_looks.py` writes the resources from
## the palette documented in `docs/CHARACTER_ART.md`.

## Material name (lower case, as the GLB names it) → the material that replaces it.
## `"<mesh node>/<material>"` (both lower case) wins over the bare name, for a material the
## model uses on two parts that need different treatment (the protagonist's hair material
## is also his eyebrows, which must not get the hair's ink line).
@export var materials: Dictionary = {}
## Blend shape → weight the face rests at (the protagonist's model ships nine shapes).
@export var expression: Dictionary = {}
## Blend shapes a blink drives to 1 and back. Empty: the character does not blink.
@export var blink_shapes: PackedStringArray = PackedStringArray()
## Seconds between blinks, a random value in [x, y].
@export var blink_interval: Vector2 = Vector2(2.5, 5.0)
@export var blink_duration: float = 0.16
## A short name for logs and reports.
@export var label: String = ""


## The replacement for `material_name` on the mesh node `mesh_name`, or null to keep the
## GLB's own material.
func material_for(mesh_name: String, material_name: String) -> Material:
	var specific := "%s/%s" % [mesh_name.to_lower(), material_name.to_lower()]
	if materials.has(specific):
		return materials[specific] as Material
	return materials.get(material_name.to_lower(), null) as Material
