"""Regenerates the street and residential-area blockouts.

The geometry stays in one box table per space so it can be reviewed and edited
here instead of in a thousand-line .tscn. The green animal
(`scenes/environment/fauna/green_animal.tscn`) is authored by hand, because its
shape is a narrative decision, not a blockout.

Run from the repository root: `python3 tools/build_outdoor_locations.py [location ...]`
(no argument rewrites every location; see `main()` for why naming one matters).
"""
import math
import os
import sys

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
        self.props = []      # (name, scene path, pos, degrees) — an imported model wrapper
        self.interactables = []
        self.exits = []
        self.spawns = []
        self.ambience = None
        self.ramps = []      # (name, pos, size, rotation radians) - collision only, see _ramp


    def box(self, name, pos, size, mat, group=None, body=True):
        self.boxes.append((name, pos, size, mat, group, body))

    def ramp(self, name, pos, size, rotation):
        self.ramps.append((name, pos, size, rotation))

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

        # Model wrappers are hand-authored scenes under scenes/environment/, never files
        # this script writes: the generator only decides *where* one stands, so a
        # regeneration cannot overwrite the wrapper or its collision (issue #21).
        prop_ids = {}
        for item in self.props:
            if item[1] not in prop_ids:
                prop_ids[item[1]] = f'{base + 6 + len(prop_ids)}_prop'
                ext.append(('PackedScene', item[1], prop_ids[item[1]]))

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
        for index, (name, pos, size, rotation) in enumerate(self.ramps):
            subs.append((f'RampShape_{index}', 'BoxShape3D', 'size = Vector3(%s, %s, %s)' % tuple(size)))

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

        for index, (name, pos, size, rotation) in enumerate(self.ramps):
            lines.append(f'[node name="{name}" type="StaticBody3D" parent="."]')
            lines.append('position = %s' % v3(pos))
            lines.append('rotation = %s' % v3(rotation))
            lines.append('')
            lines.append(f'[node name="CollisionShape3D" type="CollisionShape3D" parent="{name}"]')
            lines.append(f'shape = SubResource("RampShape_{index}")')
            lines.append('')

        for name, scene_path, pos, degrees in self.props:
            lines.append(f'[node name="{name}" parent="." instance=ExtResource("{prop_ids[scene_path]}")]')
            lines.append('position = %s' % v3(pos))
            if degrees:
                lines.append('rotation = Vector3(0, %s, 0)' % round(math.radians(degrees), 6))
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
            _outline_lines(lines, item)
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
            _outline_lines(lines, item)
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
    s.box("KerbEast", (8.9, 0.12, -8), (0.35, 0.24, 56), "concrete")
    s.box("PavementWest", (-13, 0.075, -8), (6, 0.15, 56), "concrete")
    s.box("KerbWest", (-9.9, 0.12, -8), (0.35, 0.24, 56), "concrete")
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
    # the standing water the gutter inspection is about: a short sheet on top of the gutter
    s.box("GutterPool", (-9.2, 0.065, -22.0), (0.42, 0.01, 2.6), "glass", None, False)
    # the camera on a bracket that the school wall conversation points out
    s.box("WallCameraBracket", (-10.8, 3.4, 6.0), (0.4, 0.06, 0.06), "metal", None, False)
    s.box("WallCamera", (-10.52, 3.32, 6.0), (0.3, 0.16, 0.18), "metal", None, False)
    # The stair up to the residential area, at the north end, and where it goes.
    #
    # It used to climb nine slabs to a landing against a 3.2 m garden wall: a flight of
    # steps up to the top of a wall, with the way on left to the player's imagination. Now
    # the steps are solid, the landing runs up to the front of the flats, and the front has
    # a doorway with a short passage behind it whose far end is lit - the courtyard.
    # Twelve risers of 12.3 cm to a landing one riser higher: gentle enough for the
    # navigation bake to climb (see `_ramp`), and still clearly a flight from the street.
    flight = {"steps": 12, "rise": 1.6 / 13, "run": 0.34, "start": -34.6 + 12 * 0.34}
    street_steps = _stair(s, "Step", flight["steps"], flight["rise"], flight["run"], (8.5, 12.5),
                          None, "z", -1, flight["start"], 0.0)
    _ramp(s, "StairRamp", flight["steps"], flight["rise"], flight["run"], (8.5, 12.5), None, "z",
          -1, flight["start"], 0.0)
    s.box("StairLanding", (10.5, 0.8, -35.8), (4.0, 1.6, 2.4), "concrete")
    for step in range(0, flight["steps"], 3):
        s.box(f"StairPost_{step}",
              (12.42, round(flight["rise"] * (step + 1) + 0.45, 3),
               round(flight["start"] - flight["run"] * (step + 0.5), 3)),
              (0.06, 0.9, 0.06), "metal", None, False)
    s.box("StairRail", (12.42, 2.5, -35.8), (0.06, 0.06, 2.4), "metal", None, False)
    s.box("StairRailPost", (12.42, 2.05, -34.7), (0.06, 0.9, 0.06), "metal", None, False)
    # the front of the flats, with the doorway at the head of the stair
    s.box("FlatsFrontWest", (6.3, 3.75, -37.2), (4.6, 7.5, 0.4), "brick", ["camera_occluder"])
    s.box("FlatsFrontEast", (14.7, 3.75, -37.2), (4.6, 7.5, 0.4), "brick", ["camera_occluder"])
    s.box("FlatsFrontHeader", (10.5, 5.95, -37.2), (3.8, 3.1, 0.4), "brick", ["camera_occluder"])
    s.box("FlatsFrontPlinth", (10.5, 0.8, -37.2), (3.8, 1.6, 0.4), "concrete")
    s.box("DoorwayLintel", (10.5, 4.5, -36.96), (4.2, 0.2, 0.1), "concrete", None, False)
    s.box("DoorwayJambWest", (8.5, 3.0, -36.96), (0.2, 2.8, 0.1), "concrete", None, False)
    s.box("DoorwayJambEast", (12.5, 3.0, -36.96), (0.2, 2.8, 0.1), "concrete", None, False)
    # the passage through the block: walkable, roofed, and lit at the far end
    s.box("PassageFloor", (10.5, 0.8, -39.3), (3.8, 1.6, 4.2), "concrete")
    s.box("PassageWallWest", (8.5, 3.0, -39.3), (0.2, 2.8, 4.2), "brick")
    s.box("PassageWallEast", (12.5, 3.0, -39.3), (0.2, 2.8, 4.2), "brick")
    s.box("PassageCeiling", (10.5, 4.5, -39.3), (4.2, 0.2, 4.2), "concrete", None, False)
    s.box("PassageBack", (10.5, 3.0, -41.5), (4.2, 2.8, 0.2), "metal")
    s.box("PassageLight", (10.5, 2.7, -41.38), (1.4, 2.2, 0.04), "dusk", None, False)

    s.interactables = [
        {"name": "SchoolWallLook", "pos": (-9.4, 1.2, 6.0), "id": "street_school_wall",
         "route": "street_wall", "prompt": "Look at the school wall", "radius": 1.4,
         "outline": ("WallCamera", "WallCameraBracket")},
        {"name": "NoticeLook", "pos": (9.4, 1.2, 2.0), "id": "street_notice_pole",
         "route": "street_notice", "prompt": "Read the notice", "radius": 1.2,
         "support": ("../../NoticePole",), "outline": ("NoticePole", "NoticeSheet")},
        {"name": "GutterLook", "pos": (-9.2, 0.4, -22.0), "id": "street_gutter",
         "inspection": "street_gutter", "radius": 1.3, "outline": ("GutterPool",)},
        {"name": "ShutterLook", "pos": (9.8, 1.0, -24.0), "id": "street_shutter",
         "inspection": "street_shutter", "radius": 1.4, "outline": ("ShopShutter",)},
        {"name": "BinsLook", "pos": (11.3, 0.7, -2.0), "id": "street_bins",
         "inspection": "street_bin", "radius": 1.1, "outline": ("BinsA", "BinsB")},
        {"name": "LampLook", "pos": (10.6, 1.2, -18.0), "id": "street_lamp",
         "inspection": "street_lamp", "radius": 1.2, "support": ("../../LampPost",),
         "outline": ("LampPost", "LampHead", "LampGlow")},
    ]
    s.exits = [
        {"name": "BackToSchool", "pos": (-9.6, 0.9, 16.0), "id": "street_back_to_school",
         "prompt_key": "prompt.back_to_classroom", "radius": 1.1,
         "outline": ("SchoolExitRecess", "SchoolExitDark", "GatePillarSouth", "GatePillarNorth"),
         "scene": "res://scenes/locations/corridor/corridor.tscn", "spawn": "FromStreet",
         "id_dest": "corridor"},
        # The anchor stands in the doorway at the head of the stair, so a click on the stair
        # walks the player up it and through the door instead of stopping at the bottom.
        {"name": "ToResidential", "pos": (10.5, 2.5, -36.6), "id": "street_to_residential",
         "prompt_key": "prompt.stairs_up", "radius": 1.5,
         "outline": tuple(street_steps) + ("StairLanding", "DoorwayLintel", "DoorwayJambWest",
                                           "DoorwayJambEast", "PassageLight"),
         "scene": "res://scenes/locations/residential/residential.tscn", "spawn": "FromStreet",
         "id_dest": "residential"},
    ]
    s.spawns = [("FromCorridor", (-5.5, 0, 13.5)), ("FromResidential", (10.5, 1.6, -35.4))]
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
    # The stair up the west block: fourteen steps, a landing and the door they lead to.
    #
    # It used to stand at x = -13.6, which is inside the west block (x -21..-11): the
    # player was offered "Look up the stairs" in front of a blank wall, and the landing sat
    # 35 cm past the top step, so the spawn on it could not be routed to. It now runs up the
    # block's east face, every step solid, with the landing butted against the top step.
    # Fourteen risers of 12 cm to a landing one riser higher (see `_ramp` for why not
    # fewer, steeper ones).
    flight = {"steps": 14, "rise": 1.8 / 15, "run": 0.32, "start": -12.35 + 14 * 0.32}
    res_steps = _stair(s, "Step", flight["steps"], flight["rise"], flight["run"], (-11.0, -8.8),
                       None, "z", -1, flight["start"], 0.0)
    _ramp(s, "StairRamp", flight["steps"], flight["rise"], flight["run"], (-11.0, -8.8), None,
          "z", -1, flight["start"], 0.0)
    s.box("StairLanding", (-9.9, 0.9, -13.55), (2.2, 1.8, 2.4), "concrete")
    for step in range(0, flight["steps"], 3):
        s.box(f"StairPost_{step}",
              (-8.86, round(flight["rise"] * (step + 1) + 0.45, 3),
               round(flight["start"] - flight["run"] * (step + 0.5), 3)),
              (0.06, 0.9, 0.06), "metal", None, False)
    s.box("StairRail", (-8.86, 2.7, -13.55), (0.06, 0.06, 2.4), "metal", None, False)
    s.box("StairDoor", (-10.95, 2.85, -13.55), (0.1, 2.1, 1.1), "metal", None, False)
    s.box("StairDoorLamp", (-10.9, 4.1, -13.55), (0.12, 0.15, 0.4), "lamp", None, False)

    # The way down to the street, at the courtyard's south-west corner.
    #
    # "Back to the street" used to be a point on the open south edge of the courtyard with
    # nothing there - and behind the camera, which looks north-west. It is now a stairwell
    # the camera can see: a gate at the head, thirteen solid steps going down to the west, and a
    # lit doorway at the bottom onto the street. The street's own stair comes up the same
    # 1.6 m, so the two flights agree.
    street_steps = _stair(s, "StreetStep", 13, -1.6 / 13, 0.32, None, (11.0, 14.6), "x", -1,
                          -17.0, -1.8)
    _ramp(s, "StreetStairRamp", 13, -1.6 / 13, 0.32, None, (11.0, 14.6), "x", -1, -17.0, -1.8)
    s.box("StreetStairFoot", (-21.8, -1.7, 12.8), (3.2, 0.2, 3.6), "concrete")
    s.box("StairwellWallSouth", (-20.2, -0.9, 14.8), (6.4, 1.8, 0.4), "concrete")
    s.box("StairwellBalustrade", (-20.2, 0.5, 14.8), (6.4, 1.0, 0.05), "metal")
    s.box("StairwellWallNorth", (-22.2, 0.6, 10.8), (2.4, 4.8, 0.4), "brick")
    # under the west block's south end: the flight is cut into the ground, so its north
    # side is a retaining wall up to courtyard level, not an open drop under the block
    s.box("StairwellRetainingNorth", (-19.0, -0.9, 10.8), (4.0, 1.8, 0.4), "concrete")
    # and the courtyard's own west edge south of the stairwell gets a rail, not a drop
    s.box("CourtyardWestRail", (-16.95, 0.5, 16.5), (0.1, 1.0, 3.0), "metal")
    s.box("StairwellWallWestNorth", (-23.2, -0.4, 11.1), (0.4, 2.8, 1.0), "brick")
    s.box("StairwellWallWestSouth", (-23.2, -0.4, 14.5), (0.4, 2.8, 1.0), "brick")
    s.box("StreetDoorHeader", (-23.2, 0.8, 12.8), (0.4, 0.4, 2.4), "brick", None, False)
    s.box("StreetDoorGlow", (-23.5, -0.5, 12.8), (0.2, 2.2, 2.4), "dusk")
    s.box("StreetGatePostNorth", (-16.9, 1.3, 11.15), (0.3, 2.6, 0.3), "concrete")
    s.box("StreetGatePostSouth", (-16.9, 1.3, 14.45), (0.3, 2.6, 0.3), "concrete")
    s.box("StreetGateLintel", (-16.9, 2.7, 12.8), (0.3, 0.2, 3.6), "concrete", None, False)
    s.box("StreetGateSign", (-16.72, 2.3, 12.8), (0.04, 0.4, 1.1), "paper", None, False)
    # courtyard furniture
    s.box("SlideRamp", (-6.0, 0.9, -8.0), (1.2, 0.2, 4.0), "metal", None, False)
    s.box("SlideLegs", (-6.0, 0.45, -6.2), (0.9, 0.9, 0.2), "metal")
    # The courtyard bench is an authored model now (see s.props below), not three
    # boxes. Its seat plane is the same 0.51 m the grey-box seat top was, so nothing
    # that leaned on the old seat moves.
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
    # The lane goes on: the back wall is two piers and a lintel with the lane's continuation
    # behind them, lit at its far end, instead of a blank wall the exit was pinned to.
    s.box("AlleyBackPierWest", (3.8, 2.0, -35.8), (2.0, 4.0, 0.4), "brick", ["camera_occluder"])
    s.box("AlleyBackPierEast", (8.2, 2.0, -35.8), (2.0, 4.0, 0.4), "brick", ["camera_occluder"])
    s.box("AlleyBackLintel", (6.0, 3.5, -35.8), (2.4, 1.0, 0.4), "brick", None, False)
    s.box("AlleyBeyondGround", (6.0, -0.05, -37.6), (2.4, 0.1, 3.2), "asphalt")
    s.box("AlleyBeyondWallWest", (4.7, 1.5, -37.6), (0.2, 3.0, 3.2), "brick")
    s.box("AlleyBeyondWallEast", (7.3, 1.5, -37.6), (0.2, 3.0, 3.2), "brick")
    s.box("AlleyBeyondLight", (6.0, 1.4, -39.15), (2.4, 2.8, 0.1), "dusk")
    # Real ground, flush with the courtyard's top face (y = 0) and butted against its
    # north edge at z = -22, so there is no step to fall off and nothing to fall through:
    # the lane is walkable, and the navmesh can bake it (issue #33).
    s.box("AlleyGround", (6.0, -0.05, -29.0), (6.4, 0.1, 14.0), "asphalt")
    s.box("Drain", (4.0, 0.03, 2.0), (1.2, 0.06, 0.6), "metal", None, False)

    # Imported-model hook-ups. The generator only decides *where* a wrapper stands: the
    # wrapper, its collision and its anchors are hand-authored under
    # scenes/environment/props/, so a regeneration cannot overwrite them (issue #21).
    #
    # The chair stands in a corner nobody walks through, so the pipeline keeps a real
    # instance to measure and the courtyard keeps its empty middle. The bench replaces
    # the three boxes that used to stand here, and faces -Z, towards the planter: the
    # model's back is on its -Z side, so 180 degrees turns it round. The table carries a
    # yaw only, which doubles as a guard against a prop being dropped in sideways.
    s.props = [
        ("SampleChair", "res://scenes/environment/props/sample_chair.tscn", (10.3, 0.0, 13.5), 26.0),
        ("CourtyardBench", "res://scenes/environment/props/playground_bench.tscn", (-3.2, 0.0, 6.0), 180.0),
    ]

    s.interactables = [
        {"name": "PlanterLook", "pos": (6.0, 0.8, 0.6), "id": "res_planter",
         "inspection": "res_planter", "radius": 1.4,
         "outline": ("PlanterWall", "PlanterSoil", "Hedge")},
        # The anchor sits just off the seat's front edge rather than in the middle of the
        # bench: a 1.04 m body owns its whole footprint, and an anchor inside it is hidden
        # from every standing position by the bench itself.
        {"name": "BenchLook", "pos": (-3.2, 0.63, 5.6), "id": "res_bench",
         "inspection": "res_bench", "radius": 1.2, "outline": ("CourtyardBench",)},
        {"name": "WashingLook", "pos": (-1.6, 3.4, -14.6), "id": "res_washing",
         "inspection": "res_washing", "radius": 1.6,
         "outline": ("LineA", "Shirt_0", "Shirt_1", "Shirt_2", "Shirt_3", "Towel")},
        {"name": "StainLookA", "pos": (7.8, 1.4, 10.2), "id": "res_stain_a",
         "inspection": "res_stain", "radius": 1.2, "outline": ("StainA",)},
        {"name": "StainLookB", "pos": (7.8, 1.4, -11.8), "id": "res_stain_b",
         "inspection": "res_stain", "radius": 1.2, "outline": ("StainB",)},
        {"name": "StairLook", "pos": (-9.9, 1.0, -7.0), "id": "res_stair",
         "route": "residential_stair", "prompt": "Look up the stairs", "radius": 1.5,
         "outline": tuple(res_steps) + ("StairLanding", "StairDoor")},
        {"name": "AnimalLook", "pos": (7.6, 0.9, -1.6), "id": "green_animal",
         "route": "green_animal", "prompt_key": "prompt.animal", "radius": 1.3, "animal": True},
    ]
    s.exits = [
        # On the flight itself, a few steps down: a click on the gate walks the player into
        # the stairwell before the street loads, instead of fading out on the courtyard.
        {"name": "BackToStreet", "pos": (-19.0, -0.3, 12.8), "id": "res_back_to_street",
         "prompt_key": "prompt.back_to_street", "radius": 1.4,
         "outline": tuple(street_steps) + ("StreetGatePostNorth", "StreetGatePostSouth",
                                           "StreetGateLintel", "StreetGateSign"),
         "scene": "res://scenes/locations/street/street.tscn", "spawn": "FromResidential",
         "id_dest": "street"},
        {"name": "AlleyEnd", "pos": (6.0, 0.9, -34.6), "id": "res_alley_end",
         "prompt_key": "prompt.milestone", "radius": 1.6,
         "outline": ("AlleyBackPierWest", "AlleyBackPierEast", "AlleyBackLintel", "AlleyBeyondLight"),
         "scene": "res://scenes/locations/alley/alley.tscn", "spawn": "FromCourtyard",
         "id_dest": "alley"},
    ]
    s.spawns = [
        # Arrival from the street is at the head of the stairwell it comes up.
        ("FromStreet", (-14.6, 0, 13.2)),
        ("FromStair", (-9.9, 1.8, -13.6)),
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
    # The way back: the arch out of the north block, seen from the lane side. The lane used
    # to stop at a ground edge with nothing on it, and the exit there was a prompt in the air.
    s.box("MouthPierWest", (-3.2, 2.0, 14.8), (1.6, 4.0, 0.5), "brick", ["camera_occluder"])
    s.box("MouthPierEast", (3.2, 2.0, 14.8), (1.6, 4.0, 0.5), "brick", ["camera_occluder"])
    s.box("MouthLintel", (0.0, 3.7, 14.8), (4.8, 0.6, 0.5), "brick", None, False)
    s.box("MouthThreshold", (0.0, 0.02, 14.6), (4.8, 0.04, 0.3), "concrete", None, False)
    s.box("MouthCourtyardLight", (0.0, 1.7, 15.3), (4.8, 3.4, 0.1), "dusk")

    s.interactables = [
        {"name": "NoticesLook", "pos": (3.2, 1.6, -1.9), "id": "alley_notice_wall",
         "inspection": "alley_notices", "radius": 1.3,
         "outline": tuple(f"Notice_{i}" for i in range(6))},
        {"name": "SkipLook", "pos": (-2.2, 1.0, -2.5), "id": "alley_skip",
         "inspection": "alley_bins", "radius": 1.5,
         "outline": ("SkipBody", "SkipRim", "ChairInSkip")},
        {"name": "ServiceDoorLook", "pos": (-7.4, 1.2, -12.0), "id": "alley_service_door",
         "inspection": "alley_door", "radius": 1.4, "outline": ("ServiceDoor", "ServicePlaque")},
    ]
    s.exits = [
        {"name": "BackToCourtyard", "pos": (0.0, 0.9, 12.5), "id": "alley_back_to_courtyard",
         "prompt_key": "prompt.back_to_street", "radius": 1.4,
         "outline": ("MouthPierWest", "MouthPierEast", "MouthLintel", "MouthCourtyardLight"),
         "scene": "res://scenes/locations/residential/residential.tscn", "spawn": "FromAlley",
         "id_dest": "residential"},
        {"name": "ToPlayground", "pos": (0.0, 0.9, -21.6), "id": "alley_to_playground",
         "prompt_key": "prompt.alley_gate", "radius": 1.6,
         "outline": ("GateLeaf", "GatePostWest", "GatePostEast"),
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
    # the estate gate the alley comes in through: posts, a bar over it, and the lane's light
    # beyond, so the gap in the fence reads as a way through and not as a missing panel
    # (decoration only: `tests/playground_art_slice_test.gd` pins the yard's solids and its
    # baked navigation, and the fence ends already stop the body)
    s.box("SouthGatePostWest", (-2.0, 1.25, 19.6), (0.2, 2.5, 0.2), "metal", None, False)
    s.box("SouthGatePostEast", (2.0, 1.25, 19.6), (0.2, 2.5, 0.2), "metal", None, False)
    s.box("SouthGateLintel", (0.0, 2.45, 19.6), (4.2, 0.12, 0.12), "metal", None, False)
    s.box("SouthGateLight", (0.0, 1.6, 21.9), (3.6, 3.2, 0.1), "dusk", None, False)
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

    # bench and the bag on it: both are authored models now (s.props below). The seat
    # plane is still 0.51 m and the bag still rests on it, so the yard reads the same.

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

    # The bench runs along Z, so it needs a 90 degree yaw to line up with the space the
    # grey-box seat left. -90 puts its back to the notice board and its seat towards the
    # court, which is the way the boxes already faced. The bag sits on the seat at 0.52 m
    # (its own base is 1.4 cm under its origin) and leans into the back of the bench.
    s.props = [
        ("YardBench", "res://scenes/environment/props/playground_bench.tscn", (11.0, 0.0, 3.2), -90.0),
        ("YardBag", "res://scenes/environment/props/student_backpack.tscn", (11.03, 0.52, 3.75), -90.0),
    ]

    s.interactables = [
        {"name": "HoopLook", "pos": (-8.0, 1.4, 8.8), "id": "pg_hoop_near",
         "inspection": "pg_hoop", "radius": 1.5,
         "outline": ("HoopNearPole", "HoopNearBoard", "HoopNearRim", "PlaygroundArt/Equipment/HoopNearRing")},
        {"name": "CourtLook", "pos": (0.0, 0.9, 2.0), "id": "pg_court_middle",
         "inspection": "pg_court", "radius": 1.8,
         # The painted court markings: what "the court" is, as opposed to the ground it is on.
         "outline": ("PlaygroundArt/Court",)},
        {"name": "BenchLook", "pos": (10.2, 1.0, 3.2), "id": "pg_bench_look",
         "inspection": "pg_bench", "radius": 1.4, "outline": ("YardBench", "YardBag")},
        {"name": "FrameLook", "pos": (17.0, 1.4, 9.0), "id": "pg_frame_look",
         "inspection": "pg_frame", "radius": 1.5,
         "outline": tuple(f"FramePost_{i}" for i in range(3)) + tuple(f"FrameRung_{i}" for i in range(4))
                    + ("FrameTopBar",)},
        {"name": "ShedLook", "pos": (-13.2, 1.1, -4.0), "id": "pg_shed_door",
         "route": "pg_shed", "prompt": "Try the shed", "radius": 1.5,
         "outline": ("ShedDoor", "PlaygroundArt/Equipment/ShedHasp", "PlaygroundArt/Equipment/ShedPadlock")},
        {"name": "BallLook", "pos": (-14.2, 0.8, 0.6), "id": "pg_ball_look",
         "route": "pg_ball", "prompt": "The ball under the shed", "radius": 1.4,
         "outline": ("PingPongBall",)},
        {"name": "BoardLook", "pos": (13.2, 1.7, 3.2), "id": "pg_board_look",
         "inspection": "pg_court", "radius": 1.2,
         "outline": ("BoardSheet", "BoardBacking", "BoardPostA", "BoardPostB")},
        {"name": "ContainerLook", "pos": (12.0, 1.4, -13.9), "id": "pg_container_look",
         "inspection": "pg_container", "radius": 1.8, "outline": ("ContainerDoorLine",)},
        {"name": "TyreLook", "pos": (-14.6, 0.7, 2.9), "id": "pg_tyre_look",
         "inspection": "pg_tyres", "radius": 1.4,
         # The ring tyres the art pass adds; the graybox stack they replace is hidden, and
         # hidden meshes are skipped, so listing both keeps the outline right either way.
         "outline": tuple(f"PlaygroundArt/Equipment/Tyre_{i}" for i in range(3))
                    + ("PlaygroundArt/Equipment/TyreLoose",)},
    ]
    s.exits = [
        {"name": "BackToAlley", "pos": (0.0, 0.9, 18.2), "id": "pg_back_to_alley",
         "prompt_key": "prompt.alley_gate", "radius": 1.8,
         "outline": ("SouthGatePostWest", "SouthGatePostEast", "SouthGateLintel", "SouthGateLight"),
         "scene": "res://scenes/locations/alley/alley.tscn", "spawn": "FromPlayground",
         "id_dest": "alley"},
        {"name": "BackToCorridor", "pos": (-3.0, 0.9, -19.2), "id": "pg_to_corridor",
         "prompt_key": "prompt.yard_to_corridor", "radius": 1.6, "outline": ("FireDoor", "FireStep"),
         "scene": "res://scenes/locations/corridor/corridor.tscn", "spawn": "FromSchoolyard",
         "id_dest": "corridor"},
        {"name": "FarGap", "pos": (-14.0, 0.9, -18.2), "id": "pg_gap_in_fence",
         "prompt_key": "prompt.gate_far", "radius": 1.8, "milestone": "end.slice",
         "outline": ("FenceRunGap",)},
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


def _outline_lines(lines, item):
    """Emits `outline_paths`: the meshes the highlight outline traces for this object.

    Names in the table are node paths under the location root, the same names the box
    table uses; the interactable sits under `Interactables/`, hence the `../../`. The
    schoolyard's art pass adds nodes under `PlaygroundArt/` after this script has run, and
    an object can list both its graybox box and its art replacement: the outline skips
    whichever one is hidden.
    """
    outline = item.get('outline')
    if not outline:
        return
    quoted = ", ".join(f'"../../{path}"' for path in outline)
    lines.append(f'outline_paths = PackedStringArray({quoted})')


def _stair(s, prefix, steps, rise, run, x_range, z_range, axis, direction, start, base, mat="concrete", edge=True):
    """A flight of solid steps, one box per step, each standing on `base`.

    `axis` is "x" or "z", the direction the flight climbs or descends along; `direction`
    is +1 or -1 along it; `start` is where the first step begins on that axis. `rise` is
    signed: negative for a flight that goes down. Every step is a solid block down to
    `base`, not a floating slab: seen from the side, a flight of slabs reads as a shelf.
    Returns the names of the steps, for the outline tables.
    """
    names = []
    for step in range(steps):
        top = rise * (step + 1)
        near = start + direction * run * step
        far = start + direction * run * (step + 1)
        centre = (near + far) / 2.0
        height = top - base
        y = base + height / 2.0
        if axis == "x":
            pos = (round(centre, 3), round(y, 3), round((z_range[0] + z_range[1]) / 2.0, 3))
            size = (run, round(height, 3), round(z_range[1] - z_range[0], 3))
        else:
            pos = (round((x_range[0] + x_range[1]) / 2.0, 3), round(y, 3), round(centre, 3))
            size = (round(x_range[1] - x_range[0], 3), round(height, 3), run)
        name = f"{prefix}_{step}"
        s.box(name, pos, size, mat)
        names.append(name)
        if edge:
            # A pale strip along the nosing of every tread, as on real outdoor steps. Seen
            # from the camera's height, flat-lit treads of one colour merge into a ramp; the
            # strips are what make a flight read as steps at a glance.
            # Going up, the edge a tread drops off is the one nearer the start; going down,
            # it is the far one. The strip sits on the tread, 3 cm in from that edge.
            inset = near + direction * 0.03 if rise > 0 else far - direction * 0.03
            if axis == "x":
                strip_pos = (round(inset, 3), round(top + 0.006, 3), pos[2])
                strip_size = (0.06, 0.012, size[2])
            else:
                strip_pos = (pos[0], round(top + 0.006, 3), round(inset, 3))
                strip_size = (size[0], 0.012, 0.06)
            s.box(f"{prefix}Edge_{step}", strip_pos, strip_size, "paper", None, False)
    return names


def _ramp(s, name, steps, rise, run, x_range, z_range, axis, direction, start, base):
    """An invisible slope over a flight built by `_stair`, through its nosings.

    The navigation bake voxelises at 0.25 m and may climb one voxel. On a real flight two
    neighbouring cells can sit one voxel above and one below a third, and Recast's ledge
    filter then drops the whole flight from the mesh: the stair is drawn but cannot be
    routed up, and an exit at its head sits metres off the mesh. A slope the body and the
    bake both stand on is the usual answer. Its top surface runs through the front edge of
    every tread (for a flight that goes down, through the edge each tread drops off), so it
    is never below a step and the feet stay at most one riser above a tread. It ends level
    with the top of the flight, which `_stair` callers put one riser above the last step
    (the landing or the floor the flight leads to).
    """
    thickness = 0.1
    if rise > 0:
        # up: from the floor one run before the first nosing to the landing's front edge
        a0, h0 = start - direction * run, base
        a1, h1 = start + direction * run * steps, rise * (steps + 1)
    else:
        # down: from the edge of the floor above to the floor at the foot
        a0, h0 = start, 0.0
        a1, h1 = start + direction * run * steps, rise * steps
    if a1 < a0:
        a0, h0, a1, h1 = a1, h1, a0, h0
    da, dh = a1 - a0, h1 - h0
    length = math.hypot(da, dh)
    # the box hangs under the line: its centre is half a thickness below it, on the normal
    na, nh = -dh / length, da / length
    ca = (a0 + a1) / 2.0 - na * thickness / 2.0
    ch = (h0 + h1) / 2.0 - nh * thickness / 2.0
    if axis == "z":
        width = x_range[1] - x_range[0]
        pos = (round((x_range[0] + x_range[1]) / 2.0, 4), round(ch, 4), round(ca, 4))
        size = (round(width, 3), thickness, round(length, 4))
        # local +Z onto (0, dh, da): a rotation about X of atan2(-dh, da)
        rotation = (round(math.atan2(-dh, da), 6), 0, 0)
    else:
        width = z_range[1] - z_range[0]
        pos = (round(ca, 4), round(ch, 4), round((z_range[0] + z_range[1]) / 2.0, 4))
        size = (round(length, 4), thickness, round(width, 3))
        # local +X onto (da, dh, 0): a rotation about Z of atan2(dh, da)
        rotation = (0, 0, round(math.atan2(dh, da), 6))
    s.ramp(name, pos, size, rotation)


def write(scene, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(scene.emit())
    print("wrote", path.replace(ROOT + "/", ""))


BUILDERS = {
    "street": build_street,
    "residential": build_residential,
    "alley": build_alley,
    "playground": build_playground,
}


def main(names):
    """Writes the named locations, or every location when none is named.

    The playground carries an art pass on top of the graybox
    (`scenes/environment/props/playground_art/README.md`), so rewriting it without
    re-applying that pass loses the art. Naming only the locations that changed avoids it.
    """
    unknown = [name for name in names if name not in BUILDERS]
    if unknown:
        raise SystemExit("unknown location(s): %s (known: %s)" % (", ".join(unknown), ", ".join(BUILDERS)))
    for name in names or list(BUILDERS):
        write(BUILDERS[name](), f"{ROOT}/scenes/locations/{name}/{name}.tscn")


if __name__ == "__main__":
    main(sys.argv[1:])
