# Character Rig Audit — protagonist

- Source: `D:\develop\games\where-is-school\assets\models\protagonist\protagonist.glb`
- Blender: `5.2.3 LTS`
- Rig classification: **RIGID_PART_WEIGHTED**
- Animation classification: **NO_ACTIONS**

## Summary

- Armatures: 1
- Bones / deform bones: 16 / 16
- Mesh objects: 79
- Vertices / polygons: 7633 / 12468
- Weighted / unweighted vertices: 7591 / 42
- Single-influence vertices: 7591
- Meshes with Armature modifier: 78
- Actions: 0

## Warnings

- 42 mesh vertex/vertices have no vertex-group weights.
- At least 95% of weighted vertices have exactly one influence; this is a rigid-part bind, not smooth deformation skinning.
- Armature exists but no Blender Actions were imported.

## Armatures

### `RIG_Protagonist_Blockout` (16 bones)

| Bone | Parent | Deform | Length |
|---|---|---:|---:|
| `Root` | `—` | True | 0.8400 |
| `Spine` | `Root` | True | 0.5269 |
| `Neck` | `Spine` | True | 0.0810 |
| `Head` | `Neck` | True | 0.0810 |
| `UpperArm.L` | `Spine` | True | 0.2499 |
| `LowerArm.L` | `UpperArm.L` | True | 0.2144 |
| `Hand.L` | `LowerArm.L` | True | 0.2144 |
| `UpperArm.R` | `Spine` | True | 0.2499 |
| `LowerArm.R` | `UpperArm.R` | True | 0.2144 |
| `Hand.R` | `LowerArm.R` | True | 0.2144 |
| `Thigh.L` | `Root` | True | 0.3606 |
| `Shin.L` | `Thigh.L` | True | 0.3552 |
| `Foot.L` | `Shin.L` | True | 0.3552 |
| `Thigh.R` | `Root` | True | 0.3606 |
| `Shin.R` | `Thigh.R` | True | 0.3552 |
| `Foot.R` | `Shin.R` | True | 0.3552 |

## Meshes

| Mesh | Vertices | Polygons | Armature modifier | Weighted ratio | Single influence |
|---|---:|---:|---|---:|---:|
| `Body_Cardigan_Torso` | 194 | 384 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Cardigan_Button_01` | 115 | 168 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Cardigan_Button_02` | 115 | 168 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Cardigan_Lapel_Left` | 4 | 2 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Cardigan_Lapel_Right` | 4 | 2 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Cardigan_LowerSleeve_L` | 50 | 96 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Cardigan_LowerSleeve_R` | 50 | 96 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Cardigan_Pocket` | 4 | 2 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Cardigan_UpperSleeve_L` | 50 | 96 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Cardigan_UpperSleeve_R` | 50 | 96 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Cheek_Plane_L` | 185 | 288 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Cheek_Plane_R` | 185 | 288 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Ear_Inner_L` | 115 | 168 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Ear_Inner_R` | 115 | 168 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Ear_L` | 219 | 352 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Ear_R` | 219 | 352 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Eye_Glint_L` | 97 | 140 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Eye_Glint_R` | 97 | 140 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Eye_Iris_L` | 271 | 440 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Eye_Iris_R` | 271 | 440 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Eye_Pupil_L` | 185 | 288 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Eye_Pupil_R` | 185 | 288 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Eye_Sclera_L` | 271 | 440 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Eye_Sclera_R` | 271 | 440 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Eyebrow_L` | 27 | 32 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Eyebrow_R` | 27 | 32 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Hair_Back` | 271 | 440 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Hair_Cap` | 423 | 720 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Hair_Fringe_Lock_1` | 32 | 60 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Hair_Fringe_Lock_2` | 32 | 60 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Hair_Fringe_Lock_3` | 32 | 60 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Hair_Fringe_Lock_4` | 32 | 60 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Hair_Fringe_Lock_5` | 32 | 60 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Hair_Side_Lock_L` | 32 | 60 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Hair_Side_Lock_R` | 32 | 60 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Hand_Finger_L_1` | 26 | 48 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Hand_Finger_L_2` | 26 | 48 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Hand_Finger_L_3` | 26 | 48 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Hand_Finger_R_1` | 26 | 48 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Hand_Finger_R_2` | 26 | 48 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Hand_Finger_R_3` | 26 | 48 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Hand_Palm_L` | 219 | 352 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Hand_Palm_R` | 219 | 352 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Hand_Thumb_L` | 26 | 48 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Hand_Thumb_R` | 26 | 48 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Head_Main_Mesh` | 290 | 576 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Lower_Lip_Plane` | 27 | 32 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Mouth_Line` | 36 | 48 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Neck` | 50 | 96 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Nose_Bridge` | 32 | 60 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Nose_Tip` | 185 | 288 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Nostril_Shadow_L` | 97 | 140 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Nostril_Shadow_R` | 97 | 140 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Paint_Mark_Left_Shoulder` | 4 | 2 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Paint_Mark_Lower_Cardigan` | 4 | 2 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Pocket_Stitch_Line` | 27 | 32 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Shirt_Collar_Left` | 4 | 2 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Shirt_Collar_Right` | 4 | 2 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Shirt_Front_Panel` | 4 | 2 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Shoe_L` | 271 | 440 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Shoe_R` | 271 | 440 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Shoe_Scuff_L` | 4 | 2 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Shoe_Scuff_R` | 4 | 2 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Shoe_Sole_L` | 229 | 360 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Shoe_Sole_R` | 229 | 360 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Sleeve_Cuff_L` | 34 | 64 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Sleeve_Cuff_R` | 34 | 64 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Trouser_Crease_L` | 27 | 32 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Trouser_Crease_R` | 27 | 32 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Trouser_Shin_L` | 50 | 96 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Trouser_Shin_R` | 50 | 96 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Trouser_Thigh_L` | 50 | 96 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Trouser_Thigh_R` | 50 | 96 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Trousers_Hip` | 86 | 168 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `UnderEye_Shadow_L` | 151 | 224 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `UnderEye_Shadow_R` | 151 | 224 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Upper_Eyelid_L` | 36 | 48 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Upper_Eyelid_R` | 36 | 48 | RIG_Protagonist_Blockout | 100.0% | 100.0% |
| `Icosphere` | 42 | 80 | — | 0.0% | 0.0% |

## Actions

No animation Actions were imported.

## Interpretation

This is a structural audit only. It does not judge deformation quality. Open the model in Blender and inspect elbow, knee, shoulder, hip and neck poses before approving any production animation. The source GLB was not modified.
