# Laboratory surfaces and room

The laboratory (issue #163) is a cold, chalky, over-lit room; the classroom it sits beside
is warm plaster and ochre wood under a low sun. Keeping the two apart is the whole reason
this folder exists: the room does not sample the classroom's palette, its textures, or its
materials, and the classroom does not sample this one's.

Nothing here is downloaded, traced, photographed or model-generated. Every value is
computed by the two scripts below from a fixed seed, so a reviewer can regenerate the bytes
instead of trusting a binary.

## What the room is painted from

| Field | Size | Bytes | Where it is used |
|---|---|---|---|
| `wall_plaster.png` | 1024 x 1024 | 171,178 | the shell and the partition, world-triplanar |
| `floor_concrete.png` | 1024 x 1024 | 31,283 | the laboratory floor, world-triplanar |
| `tile_glaze.png` | 512 x 512 | 3,453 | the wet bench splashback and the instrument back tile, 4 x 4 tiles of glazed ceramic |
| `bench_top.png` | 512 x 512 | 15,566 | the resin bench tops |

216 KiB together, largest file 167 KiB — inside `tools/verify_build.py`'s 512 KiB warning
budget for a texture. `wall_plaster` is the largest because it carries the tooth: a 128-cell
lattice crossing six bands, which is what gives the wall a chalky surface instead of a pale
field, and which costs about six times what a two-tone field costs.

Three rules the fields follow, and the reason each exists:

- **They tile.** Every lattice field wraps, the grout grid divides the canvas, and the
  streak columns wrap. The wall and floor materials are sampled **world-triplanar**, so a
  seam would not appear as one line: it would appear on every wall and every floor tile in
  the room.
- **They are quiet.** These are large planes read from a camera six metres above the floor.
  The room's hierarchy comes from object colour, the lamps and the cables; a texture with
  drama in it would fight the one thing in the room meant to be strange. There is no dirt,
  no grime, no damage and no stain anywhere in these four fields: a laboratory that is
  worked in is still wiped down, and the unease in this room is the cabling.
- **They band, and they band the scalar.** Each field is painted in six flat tones inside its
  own ramp, not in 18 levels of absolute colour. Quantising the finished bytes was wrong twice
  over: it threw away most of a surface's own range (a wall came out as two tones, and two
  tones on a large plane is camouflage, not plaster), and because it quantises each channel on
  its own, a ramp whose ends differ by a thousandth per channel steps red a class before green
  and blue — a tenth of every wall came out cyan. Neutral ramps plus six bands inside them,
  with the tint left to the material's `albedo_color`, is what the walls are now. The cost is
  size: per-pixel white noise at that band count came to 395 KiB for one field, so the tooth is
  a 128-cell lattice instead, and the whole set is 216 KiB.

## How to regenerate and check

```bash
python3 art/laboratory/paint_laboratory_textures.py            # rewrite the four PNGs
python3 art/laboratory/paint_laboratory_textures.py --check     # verify byte for byte
python3 tools/build_laboratory.py                               # rewrite materials + scene
python3 tools/build_laboratory.py --check                       # verify byte for byte
```

`--check` on either script exits non-zero and names the file that drifted. `godot-ci.yml`
runs both on every pull request, so a hand-edited texture or a hand-edited `.tscn` is a red
build rather than a file nobody can rebuild.

## The room itself

`tools/build_laboratory.py` emits two things from its tables:

- `assets/materials/laboratory/*.tres` — 26 `StandardMaterial3D` presets. They follow the
  ART_BIBLE rules for a location's own colour system: matte toon surfaces
  (`diffuse_mode = 3`, `specular_mode = 2`, `roughness = 1.0`), a 6 mm ink contour borrowed
  read-only from `scenes/environment/props/playground_art/materials/ink_outline.tres`, and
  the room's one chromatic events reserved for the lamps, the two running lights and the
  annex.
- `scenes/locations/laboratory/laboratory.tscn` — the scene: 167 collision boxes (each one
  the size of its own visible box mesh, and nothing else collides), 89 cylinders, 401 cable
  segments and 9 interaction anchors.

The layout, the numbers behind it and the decisions taken along the way are written up in
`docs/IMPLEMENTATION_NOTES_LABORATORY.md`.
