"""Regenerates the street and residential-area blockouts.

The geometry stays in one box table per space so it can be reviewed and edited
here instead of in a thousand-line .tscn. The green animal
(`scenes/environment/fauna/green_animal.tscn`) is authored by hand, because its
shape is a narrative decision, not a blockout.

Run from the repository root: `python3 tools/build_outdoor_locations.py`
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

MATS = {
    "asphalt": "res://assets/materials/outdoor_asphalt.tres",
    "concrete": "res://assets/materials/outdoor_concrete.tres",
    "brick": "res://assets/materials/outdoor_brick.tres",
    "hedge": "res://assets/materials/outdoor_hedge.tres",
    "shutter": "res://assets/materials/shutter_metal.tres",
    "soil": "res://assets/materials/outdoor_soil.tres",
    "lamp": "res://assets/materials/lamp_glow.tres",
    "metal": "res://assets/materials/metal_dark.tres",
    "glass": "res://assets/materials/glass_pane.tres",
    "dusk": "res://assets/materials/dusk_glow.tres",
    "wall": "res://assets/materials/wall_paint.tres",
    "floor": "res://assets/materials/floor_concrete.tres",
    "paper": "res://assets/materials/paper_pale.tres",
    "green": "res://assets/materials/animal_green.tres",
}


class Scene:
    def __init__(self, root_name, location_id):
        self.root_name = root_name
        self.location_id = location_id
        self.boxes = []      # (name, pos, size, mat, group, body)
        self.extras = []     # literal node blocks
        self.env = None
        self.sun = None
        self.interactables = []
        self.exits = []
        self.spawns = []
        self.ambience = None

    def box(self, name, pos, size, mat, group=None, body=True):
        self.boxes.append((name, pos, size, mat, group, body))

    def extra(self, text):
        self.extras.append(text)

    def emit(self):
        used = []
        for _, _, _, mat, _, _ in self.boxes:
            if mat not in used:
                used.append(mat)
        for item in self.interactables + self.exits:
            if item.get("mat") and item["mat"] not in used:
                used.append(item["mat"])

        lines = []
        ext = []
        ext.append(('Script', 'res://scripts/world/location_root.gd', '1_location_root'))
        for i, mat in enumerate(used):
            ext.append(('StandardMaterial3D', MATS[mat], f'{i + 2}_{mat}'))
        base = len(used) + 2
        ext.append(('PackedScene', 'res://scenes/interaction/interactable.tscn', f'{base}_interactable'))
        ext.append(('PackedScene', 'res://scenes/interaction/location_exit.tscn', f'{base + 1}_location_exit'))
        ext.append(('AudioStream', 'res://assets/audio/room_tone_walkway.wav', f'{base + 2}_ambience'))
        ext.append(('Script', 'res://scripts/world/ambience_player.gd', f'{base + 3}_ambience_player'))
        has_animal = any(i.get('animal') for i in self.interactables)
        if has_animal:
            ext.append(('PackedScene', 'res://scenes/environment/fauna/green_animal.tscn', f'{base + 4}_animal'))

        mat_res = {mat: f'{i + 2}_{mat}' for i, mat in enumerate(used)}

        # sub resources: one shape + one mesh per box
        subs = []
        sub_ids = []
        for index, (name, pos, size, mat, group, body) in enumerate(self.boxes):
            shape_id = f'BoxShape3D_{index}' if body else None
            mesh_id = f'BoxMesh_{index}'
            if body:
                subs.append((shape_id, 'BoxShape3D', 'size = Vector3(%s, %s, %s)' % tuple(size)))
            subs.append((mesh_id, 'BoxMesh', 'size = Vector3(%s, %s, %s)' % tuple(size)))
            sub_ids.append((shape_id, mesh_id))

        lines.append('[gd_scene load_steps=%d format=3]\n' % (len(ext) + len(subs) + 2))
        for kind, path, rid in ext:
            lines.append(f'[ext_resource type="{kind}" path="{path}" id="{rid}"]')
        lines.append('')
        lines.append('[sub_resource type="Environment" id="Environment_1"]')
        lines.append('background_mode = 1')
        lines.append('background_color = %s' % self.env['sky'])
        lines.append('ambient_light_source = 2')
        lines.append('ambient_light_color = %s' % self.env['ambient'])
        lines.append('ambient_light_energy = %s' % self.env['energy'])
        lines.append('tonemap_mode = 2')
        lines.append('fog_enabled = true')
        lines.append('fog_light_color = %s' % self.env['fog'])
        lines.append('fog_density = %s' % self.env['fog_density'])
        lines.append('adjustment_enabled = true')
        lines.append('adjustment_saturation = %s' % self.env['saturation'])
        lines.append('')
        for sid, stype, body in subs:
            lines.append(f'[sub_resource type="{stype}" id="{sid}"]')
            lines.append(body)
            lines.append('')

        def v3(v):
            return 'Vector3(%s, %s, %s)' % tuple(v)

        lines.append(f'[node name="{self.root_name}" type="Node3D"]')
        lines.append('script = ExtResource("1_location_root")')
        lines.append(f'location_id = &"{self.location_id}"')
        lines.append('')
        lines.append('[node name="WorldEnvironment" type="WorldEnvironment" parent="."]')
        lines.append('environment = SubResource("Environment_1")')
        lines.append('')
        lines.append('[node name="Sun" type="DirectionalLight3D" parent="."]')
        lines.append('rotation_degrees = %s' % v3(self.sun['rotation']))
        lines.append('light_color = %s' % self.sun['color'])
        lines.append('light_energy = %s' % self.sun['energy'])
        lines.append('shadow_enabled = true')
        lines.append('directional_shadow_max_distance = 90.0')
        lines.append('')

        for index, (name, pos, size, mat, group, body) in enumerate(self.boxes):
            shape_id, mesh_id = sub_ids[index]
            group_text = f' groups=[{", ".join(chr(34) + g + chr(34) for g in group)}]' if group else ''
            if body:
                lines.append(f'[node name="{name}" type="StaticBody3D" parent="."{group_text}]')
                lines.append('position = %s' % v3(pos))
                lines.append('')
                lines.append(f'[node name="CollisionShape3D" type="CollisionShape3D" parent="{name}"]')
                lines.append(f'shape = SubResource("{shape_id}")')
                lines.append('')
                lines.append(f'[node name="MeshInstance3D" type="MeshInstance3D" parent="{name}"]')
                lines.append(f'mesh = SubResource("{mesh_id}")')
                lines.append(f'material_override = ExtResource("{mat_res[mat]}")')
            else:
                lines.append(f'[node name="{name}" type="MeshInstance3D" parent="."{group_text}]')
                lines.append('position = %s' % v3(pos))
                lines.append(f'mesh = SubResource("{mesh_id}")')
                lines.append(f'material_override = ExtResource("{mat_res[mat]}")')
            lines.append('')

        if self.interactables or self.exits:
            lines.append('[node name="Interactables" type="Node3D" parent="."]')
            lines.append('')
        for item in self.interactables:
            lines.append(f'[node name="{item["name"]}" parent="Interactables" instance=ExtResource("{base}_interactable")]')
            lines.append('position = %s' % v3(item['pos']))
            lines.append(f'interact_id = &"{item["id"]}"')
            if item.get('prompt_key'):
                lines.append(f'prompt_key = "{item["prompt_key"]}"')
            if item.get('prompt'):
                lines.append(f'prompt_text = "{item["prompt"]}"')
            if item.get('inspection'):
                lines.append(f'inspection_id = &"{item["inspection"]}"')
            if item.get('route'):
                lines.append(f'conversation_route = &"{item["route"]}"')
            lines.append(f'radius = {item.get("radius", 1.1)}')
            lines.append('')
            if item.get('animal'):
                lines.append(f'[node name="GreenAnimal" parent="Interactables/{item["name"]}" instance=ExtResource("{base + 4}_animal")]')
                lines.append('position = Vector3(0, -0.35, 0)')
                lines.append('')
        for item in self.exits:
            lines.append(f'[node name="{item["name"]}" parent="Interactables" instance=ExtResource("{base + 1}_location_exit")]')
            lines.append('position = %s' % v3(item['pos']))
            lines.append(f'interact_id = &"{item["id"]}"')
            if item.get('prompt_key'):
                lines.append(f'prompt_key = "{item["prompt_key"]}"')
            if item.get('prompt'):
                lines.append(f'prompt_text = "{item["prompt"]}"')
            lines.append(f'radius = {item.get("radius", 1.2)}')
            if item.get('scene'):
                lines.append(f'destination_scene = "{item["scene"]}"')
                lines.append(f'destination_spawn = &"{item["spawn"]}"')
                lines.append(f'destination_id = &"{item["id_dest"]}"')
            if item.get('milestone'):
                lines.append('is_milestone_end = true')
                lines.append(f'end_card_key = "{item["milestone"]}"')
            lines.append('')

        lines.append('[node name="SpawnPoints" type="Node3D" parent="."]')
        lines.append('')
        for name, pos in self.spawns:
            lines.append(f'[node name="{name}" type="Marker3D" parent="SpawnPoints" groups=["spawn_point"]]')
            lines.append('position = %s' % v3(pos))
            lines.append('')
        lines.append('[node name="Ambience" type="AudioStreamPlayer" parent="."]')
        lines.append(f'stream = ExtResource("{base + 2}_ambience")')
        lines.append('volume_db = %s' % self.ambience['volume'])
        lines.append(f'script = ExtResource("{base + 3}_ambience_player")')
        lines.append('target_db = %s' % self.ambience['target'])
        lines.append('')
        return '\n'.join(lines)


def build_street():
    s = Scene("Street", "street")
    s.env = {
        'sky': 'Color(0.243, 0.196, 0.176, 1)',
        'ambient': 'Color(0.44, 0.34, 0.28, 1)',
        'energy': '0.55',
        'fog': 'Color(0.32, 0.24, 0.2, 1)',
        'fog_density': '0.012',
        'saturation': '0.85',
    }
    s.sun = {'rotation': (-14, 38, 0), 'color': 'Color(1, 0.66, 0.42, 1)', 'energy': 1.5}
    s.ambience = {'volume': -16.0, 'target': -24.0}

    # ground and pavements
    s.box("Road", (0, -0.1, -8), (22, 0.2, 56), "asphalt")
    s.box("PavementEast", (13, 0.075, -8), (8, 0.15, 56), "concrete")
    s.box("KerbEast", (8.9, 0.14, -8), (0.35, 0.28, 56), "concrete")
    s.box("PavementWest", (-13, 0.075, -8), (6, 0.15, 56), "concrete")
    s.box("KerbWest", (-9.9, 0.14, -8), (0.35, 0.28, 56), "concrete")
    # school building along the west side
    s.box("SchoolBlock", (-16, 6.5, -6), (10, 13, 44), "wall", ["camera_occluder"])
    s.box("SchoolPlinth", (-16, 0.6, -6), (10.2, 1.2, 44), "concrete")
    s.box("SchoolExitRecess", (-10.4, 1.4, 16), (1.2, 2.8, 4), "concrete", None, False)
    s.box("SchoolExitDark", (-10.9, 1.4, 16), (0.1, 2.6, 3.4), "metal", None, False)
    # gate pillars
    s.box("GatePillarSouth", (-10.2, 1.6, 18.4), (0.8, 3.2, 0.8), "concrete")
    s.box("GatePillarNorth", (-10.2, 1.6, 13.6), (0.8, 3.2, 0.8), "concrete")
    # east side buildings
    s.box("FlatBlockA", (17, 5.5, 6), (10, 11, 16), "brick", ["camera_occluder"])
    s.box("FlatBlockB", (16, 7.0, -12), (8, 14, 14), "brick", ["camera_occluder"])
    s.box("ShopBlock", (14, 3.6, -24), (8, 7.2, 10), "concrete", ["camera_occluder"])
    s.box("ShopShutter", (9.85, 1.6, -24), (0.2, 3.2, 6), "shutter")
    # windows (dark glass) on the west faces of the blocks
    for i, z in enumerate((12.5, 9.5, 6.5, 3.5, 0.5)):
        for j, y in enumerate((4.2, 7.4)):
            s.box(f"WindowA_{i}_{j}", (11.9, y, z), (0.12, 1.6, 1.4), "glass", None, False)
    for i, z in enumerate((-7.0, -10.0, -13.0, -16.0)):
        for j, y in enumerate((3.6, 6.8, 10.0)):
            s.box(f"WindowB_{i}_{j}", (11.9, y, z), (0.12, 1.5, 1.3), "glass", None, False)
    s.box("LitWindow", (11.85, 6.8, -13.0), (0.14, 1.5, 1.3), "dusk", None, False)
    # street furniture
    s.box("LampPost", (10.6, 3.1, -18), (0.24, 6.2, 0.24), "metal")
    s.box("LampHead", (10.6, 6.1, -18), (1.5, 0.3, 0.5), "metal", None, False)
    s.box("LampGlow", (10.5, 5.95, -18), (1.2, 0.06, 0.4), "lamp", None, False)
    s.box("NoticePole", (9.4, 1.4, 2.0), (0.14, 2.8, 0.14), "metal")
    s.box("NoticeSheet", (9.32, 2.0, 2.0), (0.04, 0.6, 0.42), "paper", None, False)
    s.box("BinsA", (10.9, 0.55, -2), (0.7, 1.1, 0.7), "shutter")
    s.box("BinsB", (11.8, 0.55, -2), (0.7, 1.1, 0.7), "metal")
    s.box("Gutter", (-9.2, 0.03, -8), (0.5, 0.06, 54), "metal", None, False)
    s.box("DrainCover", (-9.2, 0.08, -30), (0.9, 0.1, 0.9), "metal", None, False)
    # the stair up to the residential area, at the north end
    for step in range(9):
        s.box(f"Step_{step}", (10.5, 0.16 * (step + 1) - 0.08, -32.0 - 0.34 * step), (4.0, 0.16, 0.34), "concrete")
    s.box("StairLanding", (10.5, 1.5, -35.4), (4.0, 0.2, 1.6), "concrete")
    s.box("StairRail", (12.4, 2.1, -34.0), (0.1, 1.0, 4.4), "metal", None, False)
    s.box("AlleyWall", (10.5, 1.6, -37.0), (8.0, 3.2, 0.4), "brick", ["camera_occluder"])

    s.interactables = [
        {"name": "SchoolWallLook", "pos": (-9.4, 1.2, 6.0), "id": "street_school_wall",
         "route": "street_wall", "prompt": "Look at the school wall", "radius": 1.4},
        {"name": "NoticeLook", "pos": (9.4, 1.2, 2.0), "id": "street_notice_pole",
         "route": "street_notice", "prompt": "Read the notice", "radius": 1.2},
        {"name": "GutterLook", "pos": (-9.2, 0.4, -22.0), "id": "street_gutter",
         "inspection": "street_gutter", "radius": 1.3},
        {"name": "ShutterLook", "pos": (9.8, 1.0, -24.0), "id": "street_shutter",
         "inspection": "street_shutter", "radius": 1.4},
        {"name": "BinsLook", "pos": (11.3, 0.7, -2.0), "id": "street_bins",
         "inspection": "street_bin", "radius": 1.1},
        {"name": "LampLook", "pos": (10.6, 1.2, -18.0), "id": "street_lamp",
         "inspection": "street_lamp", "radius": 1.2},
    ]
    s.exits = [
        {"name": "BackToSchool", "pos": (-9.6, 0.9, 16.0), "id": "street_back_to_school",
         "prompt_key": "prompt.back_inside", "radius": 1.1,
         "scene": "res://scenes/locations/corridor/corridor.tscn", "spawn": "FromStreet",
         "id_dest": "corridor"},
        {"name": "ToResidential", "pos": (10.5, 1.0, -30.4), "id": "street_to_residential",
         "prompt_key": "prompt.stairs_up", "radius": 1.5,
         "scene": "res://scenes/locations/residential/residential.tscn", "spawn": "FromStreet",
         "id_dest": "residential"},
    ]
    s.spawns = [("FromCorridor", (-8.0, 0, 16.0)), ("FromResidential", (10.5, 1.6, -34.4))]
    return s


def build_residential():
    s = Scene("Residential", "residential")
    s.env = {
        'sky': 'Color(0.22, 0.18, 0.17, 1)',
        'ambient': 'Color(0.4, 0.32, 0.27, 1)',
        'energy': '0.5',
        'fog': 'Color(0.3, 0.23, 0.2, 1)',
        'fog_density': '0.015',
        'saturation': '0.82',
    }
    s.sun = {'rotation': (-10, 208, 0), 'color': 'Color(1, 0.62, 0.4, 1)', 'energy': 1.25}
    s.ambience = {'volume': -16.0, 'target': -24.0}

    s.box("Courtyard", (0, -0.1, -2), (34, 0.2, 40), "concrete")
    s.box("PathNorth", (0, 0.02, -24), (6, 0.06, 12), "asphalt", None, False)
    # three blocks around the courtyard
    s.box("BlockNorth", (0, 8.5, -22), (34, 17, 10), "brick", ["camera_occluder"])
    s.box("BlockWest", (-16, 7.0, -2), (10, 14, 26), "brick", ["camera_occluder"])
    s.box("BlockEast", (16, 7.5, 0), (10, 15, 22), "brick", ["camera_occluder"])
    for i, x in enumerate((-10.0, -5.0, 0.0, 5.0, 10.0)):
        for j, y in enumerate((3.5, 6.5, 9.5, 12.5)):
            s.box(f"WinN_{i}_{j}", (x, y, -16.9), (1.5, 1.3, 0.12), "glass", None, False)
    for i, z in enumerate((-11.0, -6.0, -1.0, 4.0, 9.0)):
        for j, y in enumerate((3.2, 6.2, 9.2)):
            s.box(f"WinW_{i}_{j}", (-10.9, y, z), (0.12, 1.2, 1.4), "glass", None, False)
    for i, z in enumerate((-8.0, -3.0, 2.0, 7.0)):
        for j, y in enumerate((3.4, 6.4, 9.4)):
            s.box(f"WinE_{i}_{j}", (10.9, y, z), (0.12, 1.2, 1.4), "glass", None, False)
    s.box("LitWindowN", (5.0, 6.5, -16.85), (1.5, 1.3, 0.14), "dusk", None, False)
    # the stair between the west and north block: eleven steps and a landing
    for step in range(11):
        s.box(f"Step_{step}", (-13.6, 0.15 * (step + 1) - 0.075, -9.2 - 0.3 * step),
              (3.4, 0.15, 0.3), "concrete")
    s.box("StairLanding", (-13.6, 1.75, -13.6), (3.4, 0.2, 1.8), "concrete")
    s.box("StairRail", (-15.2, 2.4, -11.0), (0.1, 1.0, 4.6), "metal", None, False)
    # courtyard furniture
    s.box("SlideRamp", (-6.0, 0.9, -8.0), (1.2, 0.2, 4.0), "metal", None, False)
    s.box("SlideLegs", (-6.0, 0.45, -6.2), (0.9, 0.9, 0.2), "metal")
    s.box("BenchSeat", (-3.2, 0.45, 6.0), (2.6, 0.12, 0.7), "floor")
    s.box("BenchLegA", (-4.3, 0.22, 6.0), (0.12, 0.45, 0.6), "metal", None, False)
    s.box("BenchLegB", (-2.1, 0.22, 6.0), (0.12, 0.45, 0.6), "metal", None, False)
    # planter with a cut hedge, and the wet patch where something was lying
    s.box("PlanterWall", (6.0, 0.25, -2.0), (5.0, 0.5, 3.0), "concrete")
    s.box("PlanterSoil", (6.0, 0.52, -2.0), (4.6, 0.1, 2.6), "soil", None, False)
    s.box("Hedge", (6.0, 1.0, -2.6), (4.6, 0.9, 1.6), "hedge", None, False)
    s.box("WetPatch", (7.2, 0.51, -0.9), (1.6, 0.02, 1.0), "asphalt", None, False)
    # washing line between two north-block windows
    s.box("LineA", (-2.0, 4.2, -16.4), (0.03, 0.03, 3.0), "metal", None, False)
    for i, x in enumerate((-2.9, -2.2, -1.5, -0.8)):
        s.box(f"Shirt_{i}", (x, 3.6, -16.0), (0.05, 1.0, 0.7), "paper", None, False)
    s.box("Towel", (0.1, 3.5, -16.0), (0.05, 1.2, 0.9), "concrete", None, False)
    # two identical wall fragments with the same stain: the courtyard repeats itself
    s.box("WallFragmentA", (8.6, 1.3, 10.0), (0.4, 2.6, 4.0), "concrete", ["camera_occluder"])
    s.box("WallFragmentB", (8.6, 1.3, -12.0), (0.4, 2.6, 4.0), "concrete", ["camera_occluder"])
    for name, z in (("StainA", 10.2), ("StainB", -11.8)):
        s.box(name, (8.4, 1.5, z), (0.06, 0.5, 0.35), "soil", None, False)
    # the alley the animal walks towards
    s.box("AlleyWallWest", (3.0, 2.0, -28.0), (0.4, 4.0, 8.0), "brick", ["camera_occluder"])
    s.box("AlleyWallEast", (9.0, 2.0, -28.0), (0.4, 4.0, 8.0), "brick", ["camera_occluder"])
    s.box("AlleyGround", (6.0, 0.02, -30.0), (5.6, 0.04, 12.0), "asphalt", None, False)
    s.box("Drain", (4.0, 0.03, 2.0), (1.2, 0.06, 0.6), "metal", None, False)

    s.interactables = [
        {"name": "PlanterLook", "pos": (6.0, 0.8, 0.6), "id": "res_planter",
         "inspection": "res_planter", "radius": 1.4},
        {"name": "BenchLook", "pos": (-3.2, 0.6, 6.0), "id": "res_bench",
         "inspection": "res_bench", "radius": 1.2},
        {"name": "WashingLook", "pos": (-1.6, 3.4, -14.6), "id": "res_washing",
         "inspection": "res_washing", "radius": 1.6},
        {"name": "StainLookA", "pos": (7.8, 1.4, 10.2), "id": "res_stain_a",
         "inspection": "res_stain", "radius": 1.2},
        {"name": "StainLookB", "pos": (7.8, 1.4, -11.8), "id": "res_stain_b",
         "inspection": "res_stain", "radius": 1.2},
        {"name": "StairLook", "pos": (-13.6, 1.0, -8.6), "id": "res_stair",
         "route": "residential_stair", "prompt": "Look up the stairs", "radius": 1.5},
        {"name": "AnimalLook", "pos": (7.6, 0.9, -1.6), "id": "green_animal",
         "route": "green_animal", "prompt_key": "prompt.animal", "radius": 1.3, "animal": True},
    ]
    s.exits = [
        {"name": "BackToStreet", "pos": (-6.0, 0.9, 15.0), "id": "res_back_to_street",
         "prompt_key": "prompt.back_to_street", "radius": 1.3,
         "scene": "res://scenes/locations/street/street.tscn", "spawn": "FromResidential",
         "id_dest": "street"},
        {"name": "AlleyEnd", "pos": (6.0, 0.9, -33.0), "id": "res_alley_end",
         "prompt_key": "prompt.milestone", "radius": 1.6, "milestone": "end.slice"},
    ]
    s.spawns = [("FromStreet", (-6.0, 0, 14.0)), ("FromStair", (-13.6, 1.8, -13.4))]
    return s


def write(scene, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(scene.emit())
    print("wrote", path.replace(ROOT + "/", ""))


write(build_street(), f"{ROOT}/scenes/locations/street/street.tscn")
write(build_residential(), f"{ROOT}/scenes/locations/residential/residential.tscn")
