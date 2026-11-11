# Mesh Component Audit — q

- Source: `D:\develop\games\where-is-school\art\character_rigging\q\q_unrigged_source.glb`
- Blender: `5.2.3 LTS`

## Summary

- Mesh objects: 8
- Vertices / polygons: 18073 / 35512
- Connected components (edge-connected): 73
- Objects with multiple components: 6

## Component inventory

A component is a set of vertices connected through mesh edges. Separate components can be split into distinct objects without cutting topology. A single component may still contain multiple semantic regions, so a one-component result does not prove that a mesh should use one bone.

| Object | Components | Component | Vertices | Polygons | World size (X × Y × Z) | World centroid | Materials |
|---|---:|---:|---:|---:|---|---|---|
| `Icosphere` | 1 | 0 | 42 | 80 | 1.902 × 2.000 × 2.000 | 0.000, 0.000, -0.000 | <no material> |
| `Q_Collar` | 1 | 0 | 637 | 1152 | 0.202 × 0.182 × 0.022 | -0.002, -0.018, 1.315 | Q_Mat_collar |
| `Q_Hair` | 14 | 0 | 2324 | 4516 | 0.247 × 0.218 × 0.216 | 0.008, -0.008, 1.579 | Q_Mat_hair |
| `Q_Hair` | 14 | 1 | 100 | 196 | 0.035 × 0.025 × 0.088 | 0.067, 0.063, 1.495 | Q_Mat_hair |
| `Q_Hair` | 14 | 2 | 100 | 196 | 0.038 × 0.019 × 0.088 | -0.043, 0.077, 1.502 | Q_Mat_hair |
| `Q_Hair` | 14 | 3 | 100 | 196 | 0.040 × 0.015 × 0.088 | 0.013, 0.083, 1.498 | Q_Mat_hair |
| `Q_Hair` | 14 | 4 | 100 | 196 | 0.095 × 0.043 × 0.026 | -0.025, 0.021, 1.616 | Q_Mat_hair |
| `Q_Hair` | 14 | 5 | 100 | 196 | 0.087 × 0.054 × 0.032 | 0.047, 0.019, 1.610 | Q_Mat_hair |
| `Q_Hair` | 14 | 6 | 100 | 196 | 0.028 × 0.034 × 0.066 | 0.113, -0.047, 1.544 | Q_Mat_hair |
| `Q_Hair` | 14 | 7 | 100 | 196 | 0.033 × 0.036 × 0.063 | -0.106, -0.020, 1.559 | Q_Mat_hair |
| `Q_Hair` | 14 | 8 | 100 | 196 | 0.061 × 0.049 × 0.059 | 0.019, -0.110, 1.595 | Q_Mat_hair |
| `Q_Hair` | 14 | 9 | 100 | 196 | 0.035 × 0.026 × 0.060 | 0.064, -0.105, 1.568 | Q_Mat_hair |
| `Q_Hair` | 14 | 10 | 100 | 196 | 0.037 × 0.036 × 0.054 | 0.027, -0.126, 1.573 | Q_Mat_hair |
| `Q_Hair` | 14 | 11 | 100 | 196 | 0.047 × 0.029 × 0.050 | -0.007, -0.127, 1.574 | Q_Mat_hair |
| `Q_Hair` | 14 | 12 | 100 | 196 | 0.047 × 0.029 × 0.049 | -0.039, -0.118, 1.577 | Q_Mat_hair |
| `Q_Hair` | 14 | 13 | 100 | 196 | 0.039 × 0.027 × 0.057 | -0.070, -0.089, 1.577 | Q_Mat_hair |
| `Q_Head` | 22 | 0 | 4514 | 9024 | 0.226 × 0.236 × 0.257 | -0.000, -0.032, 1.498 | Q_Mat_skin |
| `Q_Head` | 22 | 1 | 222 | 440 | 0.025 × 0.025 × 0.025 | -0.049, -0.118, 1.523 | Q_Mat_eye |
| `Q_Head` | 22 | 2 | 222 | 440 | 0.025 × 0.025 × 0.025 | 0.029, -0.130, 1.516 | Q_Mat_eye |
| `Q_Head` | 22 | 3 | 200 | 396 | 0.082 × 0.019 × 0.020 | -0.015, -0.133, 1.454 | Q_Mat_lip |
| `Q_Head` | 22 | 4 | 200 | 396 | 0.083 × 0.019 × 0.020 | -0.015, -0.127, 1.448 | Q_Mat_mouthdark |
| `Q_Head` | 22 | 5 | 152 | 300 | 0.062 × 0.016 × 0.016 | -0.016, -0.128, 1.438 | Q_Mat_lip |
| `Q_Head` | 22 | 6 | 152 | 300 | 0.037 × 0.026 × 0.013 | -0.045, -0.115, 1.562 | Q_Mat_brow |
| `Q_Head` | 22 | 7 | 152 | 300 | 0.043 × 0.016 × 0.015 | 0.032, -0.128, 1.550 | Q_Mat_brow |
| `Q_Head` | 22 | 8 | 152 | 300 | 0.050 × 0.011 × 0.011 | -0.013, -0.129, 1.449 | Q_Mat_teeth |
| `Q_Head` | 22 | 9 | 146 | 288 | 0.023 × 0.035 × 0.052 | -0.110, -0.013, 1.503 | Q_Mat_skin |
| `Q_Head` | 22 | 10 | 146 | 288 | 0.019 × 0.037 × 0.052 | 0.110, -0.040, 1.488 | Q_Mat_skin |
| `Q_Head` | 22 | 11 | 100 | 196 | 0.013 × 0.007 × 0.014 | -0.050, -0.130, 1.523 | Q_Mat_iris |
| `Q_Head` | 22 | 12 | 100 | 196 | 0.013 × 0.007 × 0.014 | 0.028, -0.141, 1.515 | Q_Mat_iris |
| `Q_Head` | 22 | 13 | 75 | 120 | 0.026 × 0.019 × 0.011 | -0.049, -0.120, 1.533 | Q_Mat_skin |
| `Q_Head` | 22 | 14 | 75 | 120 | 0.026 × 0.019 × 0.011 | 0.029, -0.132, 1.525 | Q_Mat_skin |
| `Q_Head` | 22 | 15 | 52 | 100 | 0.007 × 0.005 × 0.007 | -0.050, -0.131, 1.523 | Q_Mat_pupil |
| `Q_Head` | 22 | 16 | 52 | 100 | 0.007 × 0.005 × 0.007 | 0.028, -0.143, 1.515 | Q_Mat_pupil |
| `Q_Head` | 22 | 17 | 52 | 100 | 0.007 × 0.006 × 0.006 | -0.025, -0.153, 1.487 | Q_Mat_mouthdark |
| `Q_Head` | 22 | 18 | 52 | 100 | 0.007 × 0.006 × 0.006 | -0.008, -0.155, 1.486 | Q_Mat_mouthdark |
| `Q_Head` | 22 | 19 | 49 | 72 | 0.019 × 0.014 × 0.005 | -0.050, -0.120, 1.511 | Q_Mat_skin |
| `Q_Head` | 22 | 20 | 49 | 72 | 0.019 × 0.014 × 0.005 | 0.028, -0.132, 1.504 | Q_Mat_skin |
| `Q_Head` | 22 | 21 | 42 | 80 | 0.005 × 0.005 × 0.006 | 0.029, -0.141, 1.461 | Q_Mat_mouthdark |
| `Q_Neck_Hands` | 9 | 0 | 164 | 324 | 0.124 × 0.122 × 0.124 | 0.000, -0.005, 1.270 | Q_Mat_skin |
| `Q_Neck_Hands` | 9 | 1 | 164 | 324 | 0.116 × 0.114 × 0.116 | 0.000, -0.030, 1.440 | Q_Mat_skin |
| `Q_Neck_Hands` | 9 | 2 | 164 | 324 | 0.044 × 0.077 × 0.104 | -0.306, -0.155, 0.745 | Q_Mat_skin |
| `Q_Neck_Hands` | 9 | 3 | 164 | 324 | 0.069 × 0.105 × 0.052 | 0.256, -0.327, 1.096 | Q_Mat_skin |
| `Q_Neck_Hands` | 9 | 4 | 126 | 248 | 0.124 × 0.142 × 0.187 | 0.000, -0.018, 1.355 | Q_Mat_skin |
| `Q_Neck_Hands` | 9 | 5 | 114 | 224 | 0.032 × 0.060 × 0.076 | -0.308, -0.179, 0.691 | Q_Mat_skin |
| `Q_Neck_Hands` | 9 | 6 | 114 | 224 | 0.056 × 0.076 × 0.037 | 0.246, -0.384, 1.113 | Q_Mat_skin |
| `Q_Neck_Hands` | 9 | 7 | 86 | 168 | 0.028 × 0.034 × 0.055 | -0.307, -0.191, 0.736 | Q_Mat_skin |
| `Q_Neck_Hands` | 9 | 8 | 86 | 168 | 0.029 × 0.057 × 0.031 | 0.286, -0.336, 1.102 | Q_Mat_skin |
| `Q_Pants` | 9 | 0 | 266 | 528 | 0.400 × 0.340 × 0.260 | -0.000, 0.000, 0.920 | Q_Mat_pants |
| `Q_Pants` | 9 | 1 | 234 | 464 | 0.210 × 0.207 × 0.766 | -0.104, -0.005, 0.480 | Q_Mat_pants |
| `Q_Pants` | 9 | 2 | 234 | 464 | 0.210 × 0.207 × 0.766 | 0.104, -0.005, 0.480 | Q_Mat_pants |
| `Q_Pants` | 9 | 3 | 164 | 324 | 0.210 × 0.207 × 0.210 | -0.100, 0.000, 0.860 | Q_Mat_pants |
| `Q_Pants` | 9 | 4 | 164 | 324 | 0.176 × 0.173 × 0.176 | -0.105, -0.010, 0.480 | Q_Mat_pants |
| `Q_Pants` | 9 | 5 | 164 | 324 | 0.132 × 0.130 × 0.132 | -0.105, 0.000, 0.100 | Q_Mat_pants |
| `Q_Pants` | 9 | 6 | 164 | 324 | 0.210 × 0.207 × 0.210 | 0.100, 0.000, 0.860 | Q_Mat_pants |
| `Q_Pants` | 9 | 7 | 164 | 324 | 0.176 × 0.173 × 0.176 | 0.105, -0.010, 0.480 | Q_Mat_pants |
| `Q_Pants` | 9 | 8 | 164 | 324 | 0.132 × 0.130 × 0.132 | 0.105, 0.000, 0.100 | Q_Mat_pants |
| `Q_Shoes` | 4 | 0 | 266 | 528 | 0.150 × 0.300 × 0.110 | -0.105, -0.045, 0.055 | Q_Mat_shoes |
| `Q_Shoes` | 4 | 1 | 266 | 528 | 0.150 × 0.300 × 0.110 | 0.105, -0.045, 0.055 | Q_Mat_shoes |
| `Q_Shoes` | 4 | 2 | 170 | 336 | 0.156 × 0.312 × 0.032 | -0.105, -0.045, 0.016 | Q_Mat_sole |
| `Q_Shoes` | 4 | 3 | 170 | 336 | 0.156 × 0.312 × 0.032 | 0.105, -0.045, 0.016 | Q_Mat_sole |
| `Q_Top` | 13 | 0 | 366 | 728 | 0.450 × 0.390 × 0.280 | -0.000, -0.010, 0.930 | Q_Mat_cloth |
| `Q_Top` | 13 | 1 | 366 | 728 | 0.500 × 0.430 × 0.400 | -0.000, -0.035, 1.020 | Q_Mat_cloth |
| `Q_Top` | 13 | 2 | 366 | 728 | 0.450 × 0.330 × 0.320 | -0.000, -0.010, 1.190 | Q_Mat_cloth |
| `Q_Top` | 13 | 3 | 310 | 616 | 0.430 × 0.240 × 0.150 | -0.000, -0.005, 1.255 | Q_Mat_cloth |
| `Q_Top` | 13 | 4 | 234 | 464 | 0.230 × 0.238 × 0.505 | -0.276, -0.054, 1.014 | Q_Mat_cloth |
| `Q_Top` | 13 | 5 | 234 | 464 | 0.224 × 0.354 × 0.328 | 0.266, -0.099, 1.094 | Q_Mat_cloth |
| `Q_Top` | 13 | 6 | 182 | 360 | 0.220 × 0.200 × 0.100 | -0.000, -0.015, 1.290 | Q_Mat_cloth |
| `Q_Top` | 13 | 7 | 164 | 324 | 0.140 × 0.138 × 0.140 | -0.200, -0.005, 1.255 | Q_Mat_cloth |
| `Q_Top` | 13 | 8 | 164 | 324 | 0.120 × 0.118 × 0.120 | -0.300, -0.040, 1.000 | Q_Mat_cloth |
| `Q_Top` | 13 | 9 | 164 | 324 | 0.100 × 0.098 × 0.100 | -0.305, -0.130, 0.800 | Q_Mat_cloth |
| `Q_Top` | 13 | 10 | 164 | 324 | 0.140 × 0.138 × 0.140 | 0.200, -0.005, 1.255 | Q_Mat_cloth |
| `Q_Top` | 13 | 11 | 164 | 324 | 0.120 × 0.118 × 0.120 | 0.300, -0.060, 1.020 | Q_Mat_cloth |
| `Q_Top` | 13 | 12 | 164 | 324 | 0.100 × 0.098 × 0.100 | 0.265, -0.270, 1.080 | Q_Mat_cloth |

## Rigging interpretation

The following mesh objects contain multiple edge-connected components and are candidates for non-destructive loose-part separation on a working copy:
- `Q_Hair`: 14 components; vertex counts (largest first): 2324, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100
- `Q_Head`: 22 components; vertex counts (largest first): 4514, 222, 222, 200, 200, 152, 152, 152, 152, 146, 146, 100, 100, 75, 75, 52, 52, 52, 52, 49, 49, 42
- `Q_Neck_Hands`: 9 components; vertex counts (largest first): 164, 164, 164, 164, 126, 114, 114, 86, 86
- `Q_Pants`: 9 components; vertex counts (largest first): 266, 234, 234, 164, 164, 164, 164, 164, 164
- `Q_Shoes`: 4 components; vertex counts (largest first): 266, 266, 170, 170
- `Q_Top`: 13 components; vertex counts (largest first): 366, 366, 366, 310, 234, 234, 182, 164, 164, 164, 164, 164, 164

## Important limitations

- This is a topology inventory, not an automatic bone assignment.
- Component centroids and bounds are hints, not semantic labels; confirm the anatomy in Blender before binding.
- The script does not alter, save, or overwrite any source GLB.
- It does not test deformation quality or generate animation clips.
