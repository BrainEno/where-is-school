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
        ext.append(('Script', 'res://scripts/world/location_navigation.gd', f'{base + 5}_navigation'))
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
        lines.append('[node name="Navigation" type="NavigationRegion3D" parent="."]')
        lines.append(f'script = ExtResource("{base + 5}_navigation")')
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
            _support_lines(lines, item)
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
            _support_lines(lines, item)
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
        'ambient': 'Color(0.52, 0.43, 0.36, 1)',
        'energy': '1.05',
        'fog': 'Color(0.34, 0.27, 0.22, 1)',
        'fog_density': '0.004',
        'saturation': '0.85',
    }
    s.sun = {'rotation': (-14, 38, 0), 'color': 'Color(1, 0.72, 0.5, 1)', 'energy': 2.1}
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
         "route": "street_notice", "prompt": "Read the notice", "radius": 1.2,
         "support": ("../../NoticePole",)},
        {"name": "GutterLook", "pos": (-9.2, 0.4, -22.0), "id": "street_gutter",
         "inspection": "street_gutter", "radius": 1.3},
        {"name": "ShutterLook", "pos": (9.8, 1.0, -24.0), "id": "street_shutter",
         "inspection": "street_shutter", "radius": 1.4},
        {"name": "BinsLook", "pos": (11.3, 0.7, -2.0), "id": "street_bins",
         "inspection": "street_bin", "radius": 1.1},
        {"name": "LampLook", "pos": (10.6, 1.2, -18.0), "id": "street_lamp",
         "inspection": "street_lamp", "radius": 1.2, "support": ("../../LampPost",)},
    ]
    s.exits = [
        {"name": "BackToSchool", "pos": (-9.6, 0.9, 16.0), "id": "street_back_to_school",
         "prompt_key": "prompt.back_to_classroom", "radius": 1.1,
         "scene": "res://scenes/locations/corridor/corridor.tscn", "spawn": "FromStreet",
         "id_dest": "corridor"},
        {"name": "ToResidential", "pos": (10.5, 1.0, -30.4), "id": "street_to_residential",
         "prompt_key": "prompt.stairs_up", "radius": 1.5,
         "scene": "res://scenes/locations/residential/residential.tscn", "spawn": "FromStreet",
         "id_dest": "residential"},
    ]
    s.spawns = [("FromCorridor", (-5.5, 0, 13.5)), ("FromResidential", (10.5, 1.6, -34.4))]
    return s


def build_residential():
    s = Scene("Residential", "residential")
    s.env = {
        'sky': 'Color(0.22, 0.18, 0.17, 1)',
        'ambient': 'Color(0.5, 0.42, 0.35, 1)',
        'energy': '1.0',
        'fog': 'Color(0.32, 0.26, 0.21, 1)',
        'fog_density': '0.005',
        'saturation': '0.82',
    }
    s.sun = {'rotation': (-10, 208, 0), 'color': 'Color(1, 0.7, 0.48, 1)', 'energy': 1.9}
    s.ambience = {'volume': -16.0, 'target': -24.0}

    s.box("Courtyard", (0, -0.1, -2), (34, 0.2, 40), "concrete")
    # Three blocks around the courtyard — but the north one is split, because the alley
    # behind the flats is a passage the player walks through, not a painted strip on a
    # solid wall (issue #33). The gap (x 2.8..9.2) matches the lane's own retaining walls,
    # and the lintel keeps the facade in one piece above the first two metres of it: from
    # the courtyard this reads as a 3.4 m arch, not as a missing wall.
    s.box("BlockNorthWest", (-7.1, 8.5, -22), (19.8, 17, 10), "brick", ["camera_occluder"])
    s.box("BlockNorthEast", (13.1, 8.5, -22), (7.8, 17, 10), "brick", ["camera_occluder"])
    s.box("AlleyLintel", (6.0, 10.2, -18.0), (6.4, 13.6, 2.0), "brick", ["camera_occluder"])
    s.box("BlockWest", (-16, 7.0, -2), (10, 14, 26), "brick", ["camera_occluder"])
    s.box("BlockEast", (16, 7.5, 0), (10, 15, 22), "brick", ["camera_occluder"])
    # The north windows skip the mouth: x = 5 was the wall the alley now passes through.
    for i, x in enumerate((-10.0, -5.0, 0.0, 11.0, 14.0)):
        for j, y in enumerate((3.5, 6.5, 9.5, 12.5)):
            s.box(f"WinN_{i}_{j}", (x, y, -16.9), (1.5, 1.3, 0.12), "glass", None, False)
    for i, z in enumerate((-11.0, -6.0, -1.0, 4.0, 9.0)):
        for j, y in enumerate((3.2, 6.2, 9.2)):
            s.box(f"WinW_{i}_{j}", (-10.9, y, z), (0.12, 1.2, 1.4), "glass", None, False)
    for i, z in enumerate((-8.0, -3.0, 2.0, 7.0)):
        for j, y in enumerate((3.4, 6.4, 9.4)):
            s.box(f"WinE_{i}_{j}", (10.9, y, z), (0.12, 1.2, 1.4), "glass", None, False)
    s.box("LitWindowN", (1.0, 6.5, -16.85), (1.5, 1.3, 0.14), "dusk", None, False)
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
    # The lane runs from the courtyard's north edge to a back wall, and both retaining
    # walls reach the courtyard edge: a wall that stopped short would leave a 0.4 m slot
    # with no floor under it, and a player walking the edge would fall out of the world.
    s.box("AlleyWallWest", (3.0, 2.0, -29.0), (0.4, 4.0, 14.0), "brick", ["camera_occluder"])
    s.box("AlleyWallEast", (9.0, 2.0, -29.0), (0.4, 4.0, 14.0), "brick", ["camera_occluder"])
    s.box("AlleyBackWall", (6.0, 2.0, -35.8), (6.4, 4.0, 0.4), "brick", ["camera_occluder"])
    # Real ground, flush with the courtyard's top face (y = 0) and butted against its
    # north edge at z = -22, so there is no step to fall off and nothing to fall through:
    # the lane is walkable, and the navmesh can bake it (issue #33).
    s.box("AlleyGround", (6.0, -0.05, -29.0), (6.4, 0.1, 14.0), "asphalt")
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
         "prompt_key": "prompt.milestone", "radius": 1.6,
         "scene": "res://scenes/locations/alley/alley.tscn", "spawn": "FromCourtyard",
         "id_dest": "alley"},
    ]
    s.spawns = [
        ("FromStreet", (-4.0, 0, 10.0)),
        ("FromStair", (-13.6, 1.8, -13.4)),
        ("FromAlley", (6.0, 0, -31.0)),
    ]
    return s


def build_alley():
    """The lane behind the flats: short, walled, and with one bay wide enough
    that it is not a tube. Everything the player can reach is within a few steps
    of the gate, because an alley is a place you pass through, not a level."""
    s = Scene("Alley", "alley")
    s.env = {
        'sky': 'Color(0.2, 0.17, 0.16, 1)',
        'ambient': 'Color(0.48, 0.41, 0.35, 1)',
        'energy': '0.95',
        'fog': 'Color(0.3, 0.25, 0.21, 1)',
        'fog_density': '0.008',
        'saturation': '0.8',
    }
    s.sun = {'rotation': (-8, 196, 0), 'color': 'Color(1, 0.7, 0.48, 1)', 'energy': 1.3}
    s.ambience = {'volume': -18.0, 'target': -26.0}

    # the lane runs north from the courtyard
    s.box("LaneGround", (0, -0.1, -4), (7, 0.2, 38), "asphalt")
    s.box("LanePaving", (0, 0.01, -4), (1.4, 0.04, 38), "concrete", None, False)
    # walls, tall enough to keep the lane a lane
    s.box("WallWest", (-3.9, 2.0, -4), (0.5, 4.0, 38), "brick", ["camera_occluder"])
    s.box("WallEast", (3.9, 2.0, -4), (0.5, 4.0, 38), "brick", ["camera_occluder"])
    s.box("WallCopingWest", (-3.9, 4.1, -4), (0.7, 0.2, 38), "concrete", None, False)
    s.box("WallCopingEast", (3.9, 4.1, -4), (0.7, 0.2, 38), "concrete", None, False)
    # one bay on the west side: wider than the lane, so the space opens once
    s.box("BayBackWall", (-8.4, 2.0, -12), (0.5, 4.0, 8), "brick", ["camera_occluder"])
    s.box("BayNorthWall", (-6.2, 2.0, -16.2), (5.0, 4.0, 0.5), "brick")
    s.box("BaySouthWall", (-6.2, 2.0, -7.8), (5.0, 4.0, 0.5), "brick")
    s.box("BayGround", (-6.2, -0.09, -12), (5.0, 0.2, 8.4), "concrete")
    # service door and its plaque
    s.box("ServiceDoor", (-8.1, 1.2, -12), (0.15, 2.4, 1.2), "metal", None, False)
    s.box("ServicePlaque", (-8.0, 2.1, -12.9), (0.06, 0.3, 0.4), "paper", None, False)
    # the notices: paper stapled over paper
    for i, z in enumerate((-1.0, -1.35, -1.7, -2.05, -2.4, -2.75)):
        s.box(f"Notice_{i}", (3.62, 1.7 - (0.02 * i), z), (0.03, 0.42, 0.3), "paper", None, False)
    # skip and bins
    s.box("SkipBody", (-2.2, 0.75, -2.5), (2.0, 1.3, 3.2), "shutter")
    s.box("SkipRim", (-2.2, 1.42, -2.5), (2.1, 0.1, 3.3), "metal", None, False)
    s.box("ChairInSkip", (-2.2, 1.55, -3.2), (0.45, 0.5, 0.45), "floor", None, False)
    s.box("BinA", (2.9, 0.55, -9.0), (0.6, 1.1, 0.6), "metal")
    s.box("BinB", (2.9, 0.55, -9.8), (0.6, 1.1, 0.6), "shutter")
    # drain grate and a puddle that never dries
    s.box("Grate", (0.0, 0.02, -6.0), (0.9, 0.06, 0.9), "metal", None, False)
    s.box("Puddle", (-1.0, 0.03, -14.0), (2.2, 0.02, 1.4), "glass", None, False)
    # the estate gate at the far end: an opening in a fence, not a fortress
    s.box("FenceWest", (-2.2, 1.1, -22.6), (2.6, 2.2, 0.16), "metal", ["camera_occluder"])
    s.box("FenceEast", (2.2, 1.1, -22.6), (2.6, 2.2, 0.16), "metal", ["camera_occluder"])
    s.box("GatePostWest", (-1.0, 1.2, -22.6), (0.2, 2.4, 0.2), "metal")
    s.box("GatePostEast", (1.0, 1.2, -22.6), (0.2, 2.4, 0.2), "metal")
    s.box("GateLeaf", (-0.55, 1.05, -22.4), (1.1, 2.1, 0.08), "metal", None, False)

    s.interactables = [
        {"name": "NoticesLook", "pos": (3.2, 1.6, -1.9), "id": "alley_notice_wall",
         "inspection": "alley_notices", "radius": 1.3},
        {"name": "SkipLook", "pos": (-2.2, 1.0, -2.5), "id": "alley_skip",
         "inspection": "alley_bins", "radius": 1.5},
        {"name": "ServiceDoorLook", "pos": (-7.4, 1.2, -12.0), "id": "alley_service_door",
         "inspection": "alley_door", "radius": 1.4},
    ]
    s.exits = [
        {"name": "BackToCourtyard", "pos": (0.0, 0.9, 12.5), "id": "alley_back_to_courtyard",
         "prompt_key": "prompt.back_to_street", "radius": 1.4,
         "scene": "res://scenes/locations/residential/residential.tscn", "spawn": "FromAlley",
         "id_dest": "residential"},
        {"name": "ToPlayground", "pos": (0.0, 0.9, -21.6), "id": "alley_to_playground",
         "prompt_key": "prompt.alley_gate", "radius": 1.6,
         "scene": "res://scenes/locations/playground/playground.tscn", "spawn": "FromAlley",
         "id_dest": "playground"},
    ]
    s.spawns = [("FromCourtyard", (0.0, 0, 10.5)), ("FromPlayground", (0.0, 0, -20.0))]
    return s


def build_playground():
    """The open yard.

    Deliberately not a corridor and not a circuit: it is a rectangle you can walk
    across in any direction, with four things worth stopping for placed on three
    different sides so the player has to choose an order. The middle is left
    empty on purpose: that is the room later events and NPCs need.
    """
    s = Scene("Playground", "playground")
    s.env = {
        'sky': 'Color(0.26, 0.22, 0.2, 1)',
        'ambient': 'Color(0.54, 0.46, 0.38, 1)',
        'energy': '1.05',
        'fog': 'Color(0.34, 0.28, 0.23, 1)',
        'fog_density': '0.004',
        'saturation': '0.84',
    }
    s.sun = {'rotation': (-12, 32, 0), 'color': 'Color(1, 0.74, 0.52, 1)', 'energy': 1.9}
    s.ambience = {'volume': -17.0, 'target': -25.0}

    # ground, and the painted court on it
    s.box("YardGround", (0, -0.1, 0), (46, 0.2, 40), "concrete")
    s.box("CourtSurface", (0, 0.005, -2), (22, 0.02, 26), "asphalt", None, False)
    s.box("CourtLineSouth", (0, 0.02, 11), (22, 0.012, 0.14), "paper", None, False)
    s.box("CourtLineNorth", (0, 0.02, -15), (22, 0.012, 0.14), "paper", None, False)
    s.box("CourtLineWest", (-11, 0.02, -2), (0.14, 0.012, 26), "paper", None, False)
    s.box("CourtLineEast", (11, 0.02, -2), (0.14, 0.012, 26), "paper", None, False)
    s.box("CourtCentre", (0, 0.02, -2), (22, 0.012, 0.12), "paper", None, False)
    for name, z in (("KeyNear", 7.2), ("KeyFar", -11.2)):
        s.box(name, (0, 0.02, z), (5.0, 0.012, 3.2), "paper", None, False)
    # the far half was painted later: a slightly darker wash over it
    s.box("CourtFarHalf", (0, 0.008, -9.5), (21.8, 0.012, 11.0), "dusk", None, False)

    # the school behind the yard: a back wall, barred windows, a fire door
    s.box("SchoolBackWall", (0, 6.0, -21), (46, 12, 2.0), "wall", ["camera_occluder"])
    s.box("SchoolPlinth", (0, 0.6, -19.9), (46, 1.2, 0.4), "concrete")
    for i, x in enumerate((-16.0, -9.0, 9.0, 16.0)):
        for j, y in enumerate((3.2, 6.2)):
            s.box(f"BackWindow_{i}_{j}", (x, y, -19.85), (2.2, 1.4, 0.14), "glass", None, False)
            s.box(f"BackBars_{i}_{j}", (x, y, -19.75), (2.2, 0.05, 0.04), "metal", None, False)
    s.box("FireDoor", (-3.0, 1.3, -19.9), (1.4, 2.6, 0.14), "metal", None, False)
    s.box("FireStep", (-3.0, 0.12, -19.3), (2.0, 0.24, 1.0), "concrete", None, False)
    # the gap in the fence at the north-west: the slice ends past it
    s.box("FenceRunNorth", (10.0, 1.0, -18.6), (24, 2.0, 0.14), "metal", None, False)
    s.box("FenceRunGap", (-14.0, 1.0, -18.6), (11, 2.0, 0.14), "metal", None, False)
    s.box("FencePostGapWest", (-8.4, 1.1, -18.6), (0.16, 2.2, 0.2), "metal")
    s.box("FencePostGapEast", (-19.4, 1.1, -18.6), (0.16, 2.2, 0.2), "metal")

    # south side: the fence the gate comes through, and the estate behind it
    s.box("SouthFenceWest", (-12.5, 1.1, 19.6), (21, 2.2, 0.16), "metal", ["camera_occluder"])
    s.box("SouthFenceEast", (12.5, 1.1, 19.6), (21, 2.2, 0.16), "metal", ["camera_occluder"])
    s.box("EstateBlockSouth", (0, 5.0, 26), (46, 10, 8), "brick", ["camera_occluder"])
    # east side: flats, and the hedge that hides what is under the shed
    s.box("EstateBlockEast", (24, 6.0, -2), (8, 12, 40), "brick", ["camera_occluder"])

    # the two hoops
    for name, x in (("HoopNear", -8.0), ("HoopFar", 8.0)):
        z = 7.5 if name == "HoopNear" else -11.5
        s.box(f"{name}Pole", (x, 1.6, z), (0.18, 3.2, 0.18), "metal")
        s.box(f"{name}Board", (x, 3.05, z), (1.8, 1.1, 0.08), "paper", None, False)
        s.box(f"{name}Rim", (x, 2.6, z - 0.3), (0.05, 0.05, 0.45), "metal")
        s.box(f"{name}Footing", (x, 0.1, z), (1.2, 0.2, 1.2), "concrete")

    # the equipment shed on the west side
    s.box("ShedBody", (-17.0, 1.5, -4.0), (6.0, 3.0, 8.0), "wall", ["camera_occluder"])
    s.box("ShedRoof", (-17.0, 3.1, -4.0), (6.4, 0.2, 8.4), "metal", None, False)
    s.box("ShedDoor", (-13.95, 1.1, -4.0), (0.12, 2.2, 1.1), "hedge", None, False)
    s.box("ShedWindow", (-13.95, 1.9, -6.2), (0.1, 0.8, 1.2), "glass", None, False)
    s.box("ShedSheet", (-13.9, 1.9, -6.2), (0.08, 0.5, 0.9), "paper", None, False)
    # two footings, and the gap is only on the left one
    s.box("ShedFootingWest", (-15.6, 0.2, -0.1), (1.4, 0.4, 1.4), "concrete")
    s.box("ShedFootingEast", (-13.2, 0.3, -0.1), (1.4, 0.6, 1.4), "concrete")
    s.box("ShedHedge", (-18.5, 0.9, 0.6), (5.0, 1.6, 3.0), "hedge", None, False)
    s.box("PaleUnderHedge", (-16.6, 0.45, 0.9), (0.9, 0.05, 0.16), "paper", None, False)
    s.box("PingPongBall", (-14.4, 0.16, -0.1), (0.06, 0.06, 0.06), "paper", None, False)

    # notice board on the east side, by the bench
    s.box("BoardPostA", (14.0, 1.3, 2.0), (0.12, 2.6, 0.12), "metal")
    s.box("BoardPostB", (14.0, 1.3, 4.4), (0.12, 2.6, 0.12), "metal")
    s.box("BoardSheet", (14.0, 1.9, 3.2), (0.06, 1.1, 1.8), "paper", None, False)
    s.box("BoardBacking", (14.06, 1.9, 3.2), (0.04, 1.2, 1.9), "metal", None, False)

    # bench, with room either side of it
    s.box("BenchSeat", (11.0, 0.45, 3.2), (0.7, 0.12, 2.6), "floor")
    s.box("BenchLegA", (11.0, 0.22, 2.2), (0.6, 0.45, 0.12), "metal", None, False)
    s.box("BenchLegB", (11.0, 0.22, 4.2), (0.6, 0.45, 0.12), "metal", None, False)
    s.box("BagOnBench", (11.0, 0.72, 3.2), (0.4, 0.42, 0.8), "shutter", None, False)

    # climbing frame on the east side
    for i, z in enumerate((7.0, 9.0, 11.0)):
        s.box(f"FramePost_{i}", (18.0, 1.4, z), (0.14, 2.8, 0.14), "metal")
    for i, y in enumerate((0.9, 1.4, 1.9, 2.4)):
        s.box(f"FrameRung_{i}", (18.0, y, 9.0), (0.12, 0.12, 4.0), "metal", None, False)
    s.box("FrameTopBar", (18.0, 2.85, 9.0), (0.14, 0.14, 4.2), "metal", None, False)

    # tyres stacked against the shed: the yard's older gym, painted over twice
    for i, y in enumerate((0.12, 0.36, 0.6)):
        s.box(f"TyreStack_{i}", (-15.2, y, 2.6), (1.0, 0.22, 0.42), "metal", None, False)
    s.box("TyreLoose", (-14.1, 0.12, 3.5), (0.92, 0.22, 0.4), "metal", None, False)

    # the equipment container along the back: metal, no windows, a padlock bar
    s.box("ContainerBody", (12.0, 1.3, -15.5), (6.0, 2.6, 2.4), "metal", ["camera_occluder"])
    s.box("ContainerDoorLine", (12.0, 1.3, -14.28), (5.0, 2.2, 0.06), "shutter", None, False)
    s.box("ContainerBar", (9.4, 1.3, -14.24), (0.1, 2.2, 0.08), "metal", None, False)
    s.box("ContainerFootingA", (9.4, 0.1, -15.5), (0.8, 0.2, 2.6), "concrete")
    s.box("ContainerFootingB", (14.6, 0.1, -15.5), (0.8, 0.2, 2.6), "concrete")

    # outdoor fitness equipment along the west wall: two bars and a sit-up bench
    for i, dz in enumerate((-1.2, 1.2)):
        s.box(f"FitnessPost_{i}", (-20.6, 1.0, 6.0 + dz), (0.14, 2.0, 0.14), "metal")
    s.box("FitnessBarHigh", (-20.6, 1.95, 6.0), (0.12, 0.12, 2.6), "metal", None, False)
    s.box("FitnessBarLow", (-20.6, 1.05, 6.0), (0.12, 0.12, 2.6), "metal", None, False)
    s.box("SitupFrame", (-20.4, 0.42, 9.4), (0.9, 0.1, 1.6), "metal")
    s.box("SitupFootBar", (-20.4, 0.62, 10.2), (0.6, 0.5, 0.1), "metal", None, False)

    # birds: three silhouettes on the fence and one wire, still and unlit
    for i, (x, y, z) in enumerate(((6.2, 2.12, -18.5), (7.1, 2.12, -18.5), (-3.0, 1.75, -18.5))):
        s.box(f"Bird_{i}", (x, y, z), (0.16, 0.12, 0.22), "metal", None, False)
    s.box("BirdWire", (2.0, 2.9, -18.4), (16.0, 0.02, 0.02), "metal", None, False)

    # a tap and a drain: ordinary fittings, so the yard reads as used
    s.box("TapPost", (-6.0, 0.9, 14.0), (0.16, 1.8, 0.16), "metal")
    s.box("TapSpout", (-5.8, 1.6, 14.0), (0.4, 0.1, 0.1), "metal", None, False)
    s.box("TapDrain", (-5.4, 0.02, 14.3), (0.8, 0.06, 0.6), "metal", None, False)
    s.box("TreeTrunk", (20.0, 2.0, 15.0), (0.5, 4.0, 0.5), "soil")
    s.box("TreeCrown", (20.0, 4.6, 15.0), (3.6, 2.2, 3.6), "hedge", None, False)

    s.interactables = [
        {"name": "HoopLook", "pos": (-8.0, 1.4, 8.8), "id": "pg_hoop_near",
         "inspection": "pg_hoop", "radius": 1.5},
        {"name": "CourtLook", "pos": (0.0, 0.9, 2.0), "id": "pg_court_middle",
         "inspection": "pg_court", "radius": 1.8},
        {"name": "BenchLook", "pos": (10.2, 1.0, 3.2), "id": "pg_bench_look",
         "inspection": "pg_bench", "radius": 1.4},
        {"name": "FrameLook", "pos": (17.0, 1.4, 9.0), "id": "pg_frame_look",
         "inspection": "pg_frame", "radius": 1.5},
        {"name": "ShedLook", "pos": (-13.2, 1.1, -4.0), "id": "pg_shed_door",
         "route": "pg_shed", "prompt": "Try the shed", "radius": 1.5},
        {"name": "BallLook", "pos": (-14.2, 0.8, 0.6), "id": "pg_ball_look",
         "route": "pg_ball", "prompt": "The ball under the shed", "radius": 1.4},
        {"name": "BoardLook", "pos": (13.2, 1.7, 3.2), "id": "pg_board_look",
         "inspection": "pg_court", "radius": 1.2},
        {"name": "ContainerLook", "pos": (12.0, 1.4, -13.9), "id": "pg_container_look",
         "inspection": "pg_container", "radius": 1.8},
        {"name": "TyreLook", "pos": (-14.6, 0.7, 2.9), "id": "pg_tyre_look",
         "inspection": "pg_tyres", "radius": 1.4},
    ]
    s.exits = [
        {"name": "BackToAlley", "pos": (0.0, 0.9, 18.2), "id": "pg_back_to_alley",
         "prompt_key": "prompt.alley_gate", "radius": 1.8,
         "scene": "res://scenes/locations/alley/alley.tscn", "spawn": "FromPlayground",
         "id_dest": "alley"},
        {"name": "BackToCorridor", "pos": (-3.0, 0.9, -19.2), "id": "pg_to_corridor",
         "prompt_key": "prompt.yard_to_corridor", "radius": 1.6,
         "scene": "res://scenes/locations/corridor/corridor.tscn", "spawn": "FromSchoolyard",
         "id_dest": "corridor"},
        {"name": "FarGap", "pos": (-14.0, 0.9, -18.2), "id": "pg_gap_in_fence",
         "prompt_key": "prompt.gate_far", "radius": 1.8, "milestone": "end.slice"},
    ]
    s.spawns = [
        ("FromAlley", (0.0, 0, 16.0)),
        # The walkway's end door: this is the intended way into the yard, so the
        # player arrives from the school side rather than from the estate gate.
        ("FromCorridor", (-3.0, 0, -17.6)),
        # Kept for later arrivals: the yard is meant to be entered from more than
        # one side once there is something on the other side of the fence.
        ("FromSchool", (-3.0, 0, -17.4)),
    ]
    return s


def _support_lines(lines, item):
    """Emits `support_paths`, the props an interactable may be seen through.

    The generated scenes used to be hand-edited for this, which meant the next run of
    this script quietly deleted it: a notice on a pole would then be occluded by its own
    pole. It belongs in the table like every other interaction property.
    """
    support = item.get('support')
    if not support:
        return
    quoted = ", ".join(f'"{path}"' for path in support)
    lines.append(f'support_paths = PackedStringArray({quoted})')


def write(scene, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(scene.emit())
    print("wrote", path.replace(ROOT + "/", ""))


write(build_street(), f"{ROOT}/scenes/locations/street/street.tscn")
write(build_residential(), f"{ROOT}/scenes/locations/residential/residential.tscn")
write(build_alley(), f"{ROOT}/scenes/locations/alley/alley.tscn")
write(build_playground(), f"{ROOT}/scenes/locations/playground/playground.tscn")
