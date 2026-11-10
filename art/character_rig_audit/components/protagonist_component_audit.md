# Mesh Component Audit — protagonist

- Source: `D:\develop\games\where-is-school\assets\models\protagonist\protagonist.glb`
- Blender: `5.2.3 LTS`

## Summary

- Mesh objects: 79
- Vertices / polygons: 7633 / 12468
- Connected components (edge-connected): 79
- Objects with multiple components: 0

## Component inventory

A component is a set of vertices connected through mesh edges. Separate components can be split into distinct objects without cutting topology. A single component may still contain multiple semantic regions, so a one-component result does not prove that a mesh should use one bone.

| Object | Components | Component | Vertices | Polygons | World size (X × Y × Z) | World centroid | Materials |
|---|---:|---:|---:|---:|---|---|---|
| `Body_Cardigan_Torso` | 1 | 0 | 194 | 384 | 0.360 × 0.256 × 0.545 | -0.000, -0.018, 1.141 | WIS_Protagonist_Cardigan |
| `Cardigan_Button_01` | 1 | 0 | 115 | 168 | 0.018 × 0.008 × 0.018 | 0.010, -0.162, 1.190 | WIS_Protagonist_Button |
| `Cardigan_Button_02` | 1 | 0 | 115 | 168 | 0.018 × 0.008 × 0.018 | 0.010, -0.154, 1.105 | WIS_Protagonist_Button |
| `Cardigan_Lapel_Left` | 1 | 0 | 4 | 2 | 0.094 × 0.019 × 0.220 | -0.070, -0.153, 1.279 | WIS_Protagonist_Cardigan_Light |
| `Cardigan_Lapel_Right` | 1 | 0 | 4 | 2 | 0.094 × 0.019 × 0.220 | 0.070, -0.153, 1.279 | WIS_Protagonist_Cardigan_Shadow |
| `Cardigan_LowerSleeve_L` | 1 | 0 | 50 | 96 | 0.108 × 0.113 × 0.246 | -0.221, -0.093, 1.028 | WIS_Protagonist_Cardigan |
| `Cardigan_LowerSleeve_R` | 1 | 0 | 50 | 96 | 0.108 × 0.113 × 0.246 | 0.221, -0.093, 1.028 | WIS_Protagonist_Cardigan |
| `Cardigan_Pocket` | 1 | 0 | 4 | 2 | 0.051 × 0.018 × 0.070 | -0.096, -0.140, 1.119 | WIS_Protagonist_Cardigan_Light |
| `Cardigan_UpperSleeve_L` | 1 | 0 | 50 | 96 | 0.182 × 0.139 × 0.275 | -0.195, -0.059, 1.248 | WIS_Protagonist_Cardigan |
| `Cardigan_UpperSleeve_R` | 1 | 0 | 50 | 96 | 0.182 × 0.139 × 0.275 | 0.195, -0.059, 1.248 | WIS_Protagonist_Cardigan |
| `Cheek_Plane_L` | 1 | 0 | 185 | 288 | 0.054 × 0.016 × 0.038 | -0.059, -0.110, 1.513 | WIS_Protagonist_Skin_Light |
| `Cheek_Plane_R` | 1 | 0 | 185 | 288 | 0.054 × 0.016 × 0.038 | 0.057, -0.110, 1.513 | WIS_Protagonist_Skin_Light |
| `Ear_Inner_L` | 1 | 0 | 115 | 168 | 0.018 × 0.012 × 0.041 | -0.106, -0.057, 1.551 | WIS_Protagonist_Skin_Shadow |
| `Ear_Inner_R` | 1 | 0 | 115 | 168 | 0.018 × 0.012 × 0.041 | 0.106, -0.057, 1.551 | WIS_Protagonist_Skin_Shadow |
| `Ear_L` | 1 | 0 | 219 | 352 | 0.050 × 0.060 × 0.079 | -0.095, -0.035, 1.550 | WIS_Protagonist_Skin |
| `Ear_R` | 1 | 0 | 219 | 352 | 0.050 × 0.060 × 0.079 | 0.093, -0.035, 1.550 | WIS_Protagonist_Skin |
| `Eye_Glint_L` | 1 | 0 | 97 | 140 | 0.006 × 0.004 × 0.008 | -0.047, -0.144, 1.585 | WIS_Protagonist_Eye_Glint |
| `Eye_Glint_R` | 1 | 0 | 97 | 140 | 0.006 × 0.004 × 0.008 | 0.037, -0.144, 1.585 | WIS_Protagonist_Eye_Glint |
| `Eye_Iris_L` | 1 | 0 | 271 | 440 | 0.037 × 0.017 × 0.045 | -0.043, -0.132, 1.575 | WIS_Protagonist_Iris |
| `Eye_Iris_R` | 1 | 0 | 271 | 440 | 0.037 × 0.017 × 0.045 | 0.041, -0.132, 1.575 | WIS_Protagonist_Iris |
| `Eye_Pupil_L` | 1 | 0 | 185 | 288 | 0.021 × 0.011 × 0.031 | -0.042, -0.139, 1.574 | WIS_Protagonist_Pupil |
| `Eye_Pupil_R` | 1 | 0 | 185 | 288 | 0.021 × 0.011 × 0.031 | 0.042, -0.139, 1.574 | WIS_Protagonist_Pupil |
| `Eye_Sclera_L` | 1 | 0 | 271 | 440 | 0.068 × 0.028 × 0.076 | -0.045, -0.119, 1.576 | WIS_Protagonist_Eye_OffWhite |
| `Eye_Sclera_R` | 1 | 0 | 271 | 440 | 0.068 × 0.028 × 0.076 | 0.043, -0.119, 1.576 | WIS_Protagonist_Eye_OffWhite |
| `Eyebrow_L` | 1 | 0 | 27 | 32 | 0.056 × 0.029 × 0.016 | -0.054, -0.129, 1.620 | WIS_Protagonist_Hair |
| `Eyebrow_R` | 1 | 0 | 27 | 32 | 0.056 × 0.029 × 0.016 | 0.054, -0.129, 1.620 | WIS_Protagonist_Hair |
| `Hair_Back` | 1 | 0 | 271 | 440 | 0.172 × 0.154 × 0.182 | -0.002, 0.045, 1.598 | WIS_Protagonist_Hair |
| `Hair_Cap` | 1 | 0 | 423 | 720 | 0.184 × 0.210 × 0.160 | -0.002, 0.006, 1.664 | WIS_Protagonist_Hair |
| `Hair_Fringe_Lock_1` | 1 | 0 | 32 | 60 | 0.038 × 0.106 × 0.031 | -0.068, -0.069, 1.609 | WIS_Protagonist_Hair |
| `Hair_Fringe_Lock_2` | 1 | 0 | 32 | 60 | 0.036 × 0.108 × 0.051 | -0.035, -0.090, 1.633 | WIS_Protagonist_Hair_Warm |
| `Hair_Fringe_Lock_3` | 1 | 0 | 32 | 60 | 0.040 × 0.108 × 0.060 | 0.004, -0.097, 1.630 | WIS_Protagonist_Hair |
| `Hair_Fringe_Lock_4` | 1 | 0 | 32 | 60 | 0.034 × 0.101 × 0.044 | 0.042, -0.086, 1.633 | WIS_Protagonist_Hair_Warm |
| `Hair_Fringe_Lock_5` | 1 | 0 | 32 | 60 | 0.030 × 0.095 × 0.033 | 0.067, -0.062, 1.615 | WIS_Protagonist_Hair |
| `Hair_Side_Lock_L` | 1 | 0 | 32 | 60 | 0.056 × 0.080 × 0.106 | -0.079, -0.046, 1.616 | WIS_Protagonist_Hair_Warm |
| `Hair_Side_Lock_R` | 1 | 0 | 32 | 60 | 0.056 × 0.080 × 0.106 | 0.079, -0.046, 1.616 | WIS_Protagonist_Hair_Warm |
| `Hand_Finger_L_1` | 1 | 0 | 26 | 48 | 0.018 × 0.015 × 0.039 | -0.224, -0.130, 0.822 | WIS_Protagonist_Skin |
| `Hand_Finger_L_2` | 1 | 0 | 26 | 48 | 0.018 × 0.015 × 0.039 | -0.207, -0.130, 0.822 | WIS_Protagonist_Skin |
| `Hand_Finger_L_3` | 1 | 0 | 26 | 48 | 0.018 × 0.015 × 0.039 | -0.190, -0.130, 0.822 | WIS_Protagonist_Skin |
| `Hand_Finger_R_1` | 1 | 0 | 26 | 48 | 0.018 × 0.015 × 0.039 | 0.190, -0.130, 0.822 | WIS_Protagonist_Skin |
| `Hand_Finger_R_2` | 1 | 0 | 26 | 48 | 0.018 × 0.015 × 0.039 | 0.207, -0.130, 0.822 | WIS_Protagonist_Skin |
| `Hand_Finger_R_3` | 1 | 0 | 26 | 48 | 0.018 × 0.015 × 0.039 | 0.224, -0.130, 0.822 | WIS_Protagonist_Skin |
| `Hand_Palm_L` | 1 | 0 | 219 | 352 | 0.076 × 0.062 × 0.110 | -0.208, -0.111, 0.858 | WIS_Protagonist_Skin |
| `Hand_Palm_R` | 1 | 0 | 219 | 352 | 0.076 × 0.062 × 0.110 | 0.206, -0.111, 0.858 | WIS_Protagonist_Skin |
| `Hand_Thumb_L` | 1 | 0 | 26 | 48 | 0.029 × 0.032 × 0.044 | -0.170, -0.124, 0.851 | WIS_Protagonist_Skin |
| `Hand_Thumb_R` | 1 | 0 | 26 | 48 | 0.029 × 0.032 × 0.044 | 0.170, -0.124, 0.851 | WIS_Protagonist_Skin |
| `Head_Main_Mesh` | 1 | 0 | 290 | 576 | 0.188 × 0.222 × 0.274 | 0.000, -0.036, 1.569 | WIS_Protagonist_Skin |
| `Icosphere` | 1 | 0 | 42 | 80 | 1.902 × 2.000 × 2.000 | 0.000, 0.000, -0.000 | <no material> |
| `Lower_Lip_Plane` | 1 | 0 | 27 | 32 | 0.032 × 0.011 × 0.006 | 0.003, -0.143, 1.479 | WIS_Protagonist_Skin_Light |
| `Mouth_Line` | 1 | 0 | 36 | 48 | 0.057 × 0.016 × 0.012 | -0.001, -0.142, 1.488 | WIS_Protagonist_Skin_Shadow |
| `Neck` | 1 | 0 | 50 | 96 | 0.110 × 0.106 × 0.133 | 0.000, -0.055, 1.405 | WIS_Protagonist_Skin |
| `Nose_Bridge` | 1 | 0 | 32 | 60 | 0.038 × 0.058 × 0.076 | 0.000, -0.138, 1.577 | WIS_Protagonist_Skin_Light |
| `Nose_Tip` | 1 | 0 | 185 | 288 | 0.042 × 0.036 × 0.024 | -0.001, -0.151, 1.545 | WIS_Protagonist_Skin |
| `Nostril_Shadow_L` | 1 | 0 | 97 | 140 | 0.009 × 0.005 × 0.005 | -0.012, -0.164, 1.540 | WIS_Protagonist_Skin_Shadow |
| `Nostril_Shadow_R` | 1 | 0 | 97 | 140 | 0.009 × 0.005 × 0.005 | 0.012, -0.164, 1.540 | WIS_Protagonist_Skin_Shadow |
| `Paint_Mark_Left_Shoulder` | 1 | 0 | 4 | 2 | 0.040 × 0.016 × 0.041 | -0.154, -0.104, 1.318 | WIS_Protagonist_Brush_Rust |
| `Paint_Mark_Lower_Cardigan` | 1 | 0 | 4 | 2 | 0.036 × 0.005 × 0.036 | 0.098, -0.121, 0.971 | WIS_Protagonist_Cardigan_Light |
| `Pocket_Stitch_Line` | 1 | 0 | 27 | 32 | 0.043 × 0.016 × 0.006 | -0.096, -0.143, 1.140 | WIS_Protagonist_Stitch |
| `Shirt_Collar_Left` | 1 | 0 | 4 | 2 | 0.078 × 0.024 × 0.080 | -0.046, -0.158, 1.353 | WIS_Protagonist_Shirt_Shadow |
| `Shirt_Collar_Right` | 1 | 0 | 4 | 2 | 0.078 × 0.024 × 0.080 | 0.046, -0.158, 1.353 | WIS_Protagonist_Shirt |
| `Shirt_Front_Panel` | 1 | 0 | 4 | 2 | 0.118 × 0.028 × 0.260 | -0.000, -0.146, 1.235 | WIS_Protagonist_Shirt |
| `Shoe_L` | 1 | 0 | 271 | 440 | 0.146 × 0.290 × 0.104 | -0.080, -0.065, 0.085 | WIS_Protagonist_Shoes |
| `Shoe_R` | 1 | 0 | 271 | 440 | 0.146 × 0.290 × 0.104 | 0.076, -0.065, 0.085 | WIS_Protagonist_Shoes |
| `Shoe_Scuff_L` | 1 | 0 | 4 | 2 | 0.033 × 0.008 × 0.007 | -0.078, -0.203, 0.104 | WIS_Protagonist_Trousers_Light |
| `Shoe_Scuff_R` | 1 | 0 | 4 | 2 | 0.033 × 0.008 × 0.007 | 0.078, -0.203, 0.104 | WIS_Protagonist_Trousers_Light |
| `Shoe_Sole_L` | 1 | 0 | 229 | 360 | 0.146 × 0.302 × 0.054 | -0.080, -0.064, 0.044 | WIS_Protagonist_Sole |
| `Shoe_Sole_R` | 1 | 0 | 229 | 360 | 0.146 × 0.302 × 0.054 | 0.076, -0.064, 0.044 | WIS_Protagonist_Sole |
| `Sleeve_Cuff_L` | 1 | 0 | 34 | 64 | 0.081 × 0.067 × 0.036 | -0.210, -0.111, 0.915 | WIS_Protagonist_Cardigan_Light |
| `Sleeve_Cuff_R` | 1 | 0 | 34 | 64 | 0.081 × 0.067 × 0.036 | 0.210, -0.111, 0.915 | WIS_Protagonist_Cardigan_Light |
| `Trouser_Crease_L` | 1 | 0 | 27 | 32 | 0.008 × 0.012 × 0.150 | -0.088, -0.057, 0.620 | WIS_Protagonist_Trousers_Light |
| `Trouser_Crease_R` | 1 | 0 | 27 | 32 | 0.008 × 0.012 × 0.150 | 0.068, -0.057, 0.620 | WIS_Protagonist_Trousers_Light |
| `Trouser_Shin_L` | 1 | 0 | 50 | 96 | 0.110 × 0.090 × 0.368 | -0.085, -0.014, 0.339 | WIS_Protagonist_Trousers |
| `Trouser_Shin_R` | 1 | 0 | 50 | 96 | 0.110 × 0.090 × 0.368 | 0.085, -0.014, 0.339 | WIS_Protagonist_Trousers |
| `Trouser_Thigh_L` | 1 | 0 | 50 | 96 | 0.154 × 0.129 × 0.366 | -0.081, 0.002, 0.695 | WIS_Protagonist_Trousers |
| `Trouser_Thigh_R` | 1 | 0 | 50 | 96 | 0.154 × 0.129 × 0.366 | 0.081, 0.002, 0.695 | WIS_Protagonist_Trousers |
| `Trousers_Hip` | 1 | 0 | 86 | 168 | 0.278 × 0.184 × 0.165 | 0.000, 0.014, 0.835 | WIS_Protagonist_Trousers |
| `UnderEye_Shadow_L` | 1 | 0 | 151 | 224 | 0.062 × 0.011 × 0.017 | -0.046, -0.119, 1.550 | WIS_Protagonist_UnderEye |
| `UnderEye_Shadow_R` | 1 | 0 | 151 | 224 | 0.062 × 0.011 × 0.017 | 0.044, -0.119, 1.550 | WIS_Protagonist_UnderEye |
| `Upper_Eyelid_L` | 1 | 0 | 36 | 48 | 0.070 × 0.017 × 0.028 | -0.046, -0.133, 1.594 | WIS_Protagonist_Skin_Shadow |
| `Upper_Eyelid_R` | 1 | 0 | 36 | 48 | 0.070 × 0.017 × 0.028 | 0.046, -0.133, 1.594 | WIS_Protagonist_Skin_Shadow |

## Rigging interpretation

No mesh object contains multiple edge-connected components. Do not try to separate by loose parts; use a different binding strategy for any combined body mesh.

## Important limitations

- This is a topology inventory, not an automatic bone assignment.
- Component centroids and bounds are hints, not semantic labels; confirm the anatomy in Blender before binding.
- The script does not alter, save, or overwrite any source GLB.
- It does not test deformation quality or generate animation clips.
