# Protagonist Retarget Rig Preparation

- Script version: `1.0.0`
- Blender: `5.2.3 LTS`
- Source: `D:\develop\games\where-is-school\assets\models\protagonist\protagonist.glb`
- Bound mesh objects: 78
- Total skeleton bones: 21
- Deform bones: 15
- Rest-pose bounds preserved within 2 mm: **True**

## Retarget hierarchy

```text
Root
└── Hips
    ├── LeftUpperLeg → LeftLowerLeg → LeftFoot
    ├── RightUpperLeg → RightLowerLeg → RightFoot
    └── Spine → Chest → UpperChest
        ├── Neck → Head
        ├── LeftShoulder → LeftUpperArm → LeftLowerArm → LeftHand
        └── RightShoulder → RightUpperArm → RightLowerArm → RightHand
```

## Important

- Existing deform meshes and their vertex weights are retained; limb vertex groups are renamed to humanoid names.
- Added Hips/Chest/UpperChest/Shoulder bones are non-deforming hierarchy pivots.
- The unparented helper mesh (if present) is retained in the .blend but excluded from the exported character GLB.
- No animation is baked or copied. Import the Godot-ready Quaternius animation library separately and retarget it in Godot.
- Do not replace the production `assets/models/protagonist/protagonist.glb` until the Godot import and playback test passes.

## Warnings

- No animation is retargeted by this script.
- The target is A-pose-like; enable Fix Silhouette in Godot only after reviewing its import preview.
- Hands/fingers and toes remain single rigid hand/foot parts; optional finger/toe profile bones are not added.
- Keep the original protagonist.glb. Test this output before changing the production wrapper.
