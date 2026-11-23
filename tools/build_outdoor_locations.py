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

# Layer 4 is included in LocationNavigation.geometry_collision_mask and the interaction
# occluder mask, but excluded from the player's collision mask. Visible stair blocks remain
# in the bake and still occlude sight while the player rides the smooth ramp.
NAVIGATION_ONLY_LAYER = 1 << 3
# Layer 5 is for invisible bake-only treads: they complete navigation over tall landings
# without colliding with the player or blocking interaction line-of-sight.
BAKE_ONLY_LAYER = 1 << 4
# Layer 3 is in the player's collision mask but not the navigation or interaction-occluder
# masks. Thin landing-top colliders use it instead of making the tall visible plinths solid.
PLAYER_ONLY_LAYER = 1 << 2

# Layer 8 is in no body mask but the camera occluder fader's (which casts against every
# layer): nothing walks into it, clicks on it, bakes it, or is hidden from an interaction by
# it. A dead tree's fader box is on it, so the tree fades when it stands between the camera
# and the player without its twigs becoming a wall.
FADE_ONLY_LAYER = 1 << 7

# The teaching block's long front, as the front yard sees it (x -11 is its face); the stage
# pass paints the barred windows across it. North of the glass entrance's recess.
STREET_SCHOOL_Z = (-8.3, 12.7)
# ... and south of it, to the yard's south wall.
SCHOOL_SOUTH_Z = (20.0, 32.3)

# The school wall (围墙) between the front yard and the street, and the gate in it (校门):
# the retractable gate's opening (伸缩门), its pier, the side door's opening (小门), its pier.
# The street sees the wall's east face at x -11.0 (SCHOOL_WALL_X); the front yard sees its west
# face at x 15.0 (YARD_WALL_X). Both share z, so the door is at the same place either side.
# docs/GLOSSARY.md has the names.
SCHOOL_WALL_X = -11.15
YARD_WALL_X = 15.15
SCHOOL_WALL_H = 2.6
GATE_PIER = 0.6
STREET_GATE_Z = (8.5, 14.65)
STREET_DOOR_Z = (15.25, 16.35)
GATE_HEIGHT = 1.75
DOOR_HEIGHT = 2.2

# The front yard (前操场): dirt from the teaching block (west, x -11) to the school wall
# (east), with a low railing north and south and more sports ground past it. The glass entrance is the
# street's old one, where it was, so the corridor's door still lands in the same recess.
FRONT_YARD_Z = (-8.3, 32.3)
# Dead trees: (x, z, variant, yaw degrees; multiples of 90 keep the crown in its fader box).
FRONT_YARD_TREES = (
    (-6.4, 4.2, "a", 0), (-6.8, -4.0, "b", 90), (6.2, -3.6, "c", 180), (10.2, 3.6, "a", 270),
    (-6.6, 26.4, "c", 0), (3.4, 22.8, "b", 270), (11.0, 27.6, "a", 90),
)
# The box each crown grows in (front_yard_meshes.TREE_BOUNDS), as the fader's collider.
FRONT_YARD_TREE_BOX = (5.4, 7.3)

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
        self.boxes = []      # (name, pos, size, mat, group, body, collision_layer)
        self.extras = []     # literal node blocks
        self.env = None
        self.sun = None
        self.props = []      # (name, scene path, pos, degrees) — an imported model wrapper
        self.interactables = []
        self.exits = []
        self.spawns = []
        self.ambience = None
        self.ramps = []      # (name, pos, size, rotation, collision_layer) - see _ramp/_tread


    def box(self, name, pos, size, mat, group=None, body=True, collision_layer=1):
        self.boxes.append((name, pos, size, mat, group, body, collision_layer))

    def ramp(self, name, pos, size, rotation, collision_layer=1):
        self.ramps.append((name, pos, size, rotation, collision_layer))

    def extra(self, text):
        self.extras.append(text)

    def emit(self):
        used = []
        for _, _, _, mat, _, _, _ in self.boxes:
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

        shot_ids = {}
        for item in self.interactables:
            shot = item.get("shot")
            if shot and shot not in shot_ids:
                shot_ids[shot] = f"shot_{len(shot_ids)}"
                ext.append(('Resource', shot, shot_ids[shot]))

        # An interactable whose use is staged by its own script (a StagedInteractable
        # subclass that sets its handler) keeps the shared scene and swaps the script.
        script_ids = {}
        for item in self.interactables + self.exits:
            script = item.get("script")
            if script and script not in script_ids:
                script_ids[script] = f"staged_{len(script_ids)}"
                ext.append(('Script', script, script_ids[script]))

        mat_res = {mat: f'{i + 2}_{mat}' for i, mat in enumerate(used)}

        # sub resources: one shape + one mesh per box
        subs = []
        sub_ids = []
        for index, (name, pos, size, mat, group, body, collision_layer) in enumerate(self.boxes):
            shape_id = f'BoxShape3D_{index}' if body else None
            mesh_id = f'BoxMesh_{index}'
            if body:
                subs.append((shape_id, 'BoxShape3D', 'size = Vector3(%s, %s, %s)' % tuple(size)))
            subs.append((mesh_id, 'BoxMesh', 'size = Vector3(%s, %s, %s)' % tuple(size)))
            sub_ids.append((shape_id, mesh_id))
        for index, (name, pos, size, rotation, collision_layer) in enumerate(self.ramps):
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

        for index, (name, pos, size, mat, group, body, collision_layer) in enumerate(self.boxes):
            shape_id, mesh_id = sub_ids[index]
            group_text = f' groups=[{", ".join(chr(34) + g + chr(34) for g in group)}]' if group else ''
            if body:
                lines.append(f'[node name="{name}" type="StaticBody3D" parent="."{group_text}]')
                lines.append('position = %s' % v3(pos))
                if collision_layer != 1:
                    lines.append(f'collision_layer = {collision_layer}')
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

        for index, (name, pos, size, rotation, collision_layer) in enumerate(self.ramps):
            lines.append(f'[node name="{name}" type="StaticBody3D" parent="."]')
            lines.append('position = %s' % v3(pos))
            lines.append('rotation = %s' % v3(rotation))
            if collision_layer != 1:
                lines.append(f'collision_layer = {collision_layer}')
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
            if item.get('script'):
                lines.append(f'script = ExtResource("{script_ids[item["script"]]}")')
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
            if item.get('shot'):
                lines.append(f'camera_shot = ExtResource("{shot_ids[item["shot"]]}")')
            _support_lines(lines, item)
            _outline_lines(lines, item)
            lines.append('')
            if item.get('animal'):
                lines.append(f'[node name="GreenAnimal" parent="Interactables/{item["name"]}" instance=ExtResource("{base + 4}_animal")]')
                lines.append('position = Vector3(0, -0.35, 0)')
                lines.append('')
        for item in self.exits:
            lines.append(f'[node name="{item["name"]}" parent="Interactables" instance=ExtResource("{base + 1}_location_exit")]')
            if item.get('script'):
                lines.append(f'script = ExtResource("{script_ids[item["script"]]}")')
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
            if item.get('required_flag'):
                lines.append(f'required_flag = &"{item["required_flag"]}"')
                lines.append(f'blocked_inspection_id = &"{item["blocked_inspection"]}"')
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
    s.box("PavementWest", (-10.5, 0.075, -8), (1.0, 0.15, 56), "concrete")
    s.box("KerbWest", (-9.9, 0.12, -8), (0.35, 0.24, 56), "concrete")
    # The west side is the school wall (围墙), not the school: the teaching block stands back
    # behind it across the front yard (前操场), painted by the stage pass and out of reach.
    # The gate (校门) is in the wall at the south end: the retractable gate, shut, and beside
    # it the side door (小门) that goes back in. docs/GLOSSARY.md has the names.
    _school_wall(s, SCHOOL_WALL_X, (-36.0, 19.6), 1)
    # the wall's ivory foot along the street, where the receipt hatch is set
    s.box("SchoolWallDado", (-11.15, 0.6, (-36.0 + STREET_GATE_Z[0] - GATE_PIER) / 2),
          (0.5, 1.2, STREET_GATE_Z[0] - GATE_PIER + 36.0), "concrete")
    # the camera on a bracket that the school wall conversation points out, on the gate's
    # north pier, looking down past the gate at the foot of the wall
    pier_z = STREET_GATE_Z[0] - GATE_PIER / 2
    s.box("WallCameraBracket", (-10.62, 2.9, pier_z), (0.46, 0.06, 0.06), "metal", None, False)
    s.box("WallCamera", (-10.36, 2.82, pier_z), (0.3, 0.16, 0.18), "metal", None, False)
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
    # The gutter is an open ditch along the west kerb, 0.625 m wide (the kerb's face to
    # x -9.1), its water 0.38 m down. Its lining, the bank and the slabs over it are the stage
    # pass's (build_stage_art.py); the Road collider is left whole, so the walk is unchanged.
    # `Gutter` is the water from the street's north end to the slabs at the crossing.
    s.box("Gutter", (-9.4125, -0.385, -14.25), (0.625, 0.01, 43.5), "glass", None, False)
    # The cover it runs towards sits on the road, higher than the water that runs to it.
    s.box("DrainCover", (-9.4125, 0.03, -30), (0.64, 0.08, 0.8), "metal", None, False)
    # the standing water the gutter inspection is about: backed up against the cover
    s.box("GutterPool", (-9.4125, -0.375, -25.5), (0.625, 0.01, 8.2), "glass", None, False)
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
    # Keep the solid plinth visible, but do not make its full-height front face a wall
    # to the player. A 5 cm top collider lets the ramp meet the landing without the
    # step-up helper popping the capsule up the remaining ~12 cm at the last frame.
    s.box("StairLanding", (10.5, 0.8, -35.8), (4.0, 1.6, 2.4), "concrete", body=False)
    # The player collider starts 30 cm behind the visible lip: the capsule reaches the
    # landing height before its radius finds this edge; the bake tread still reaches the lip.
    _landing_surface(s, "StairLandingSurface", (8.5, 12.5), (-37.0, -34.9), 1.6)
    _tread(s, "StairLandingTread", (8.5, 12.5), (-37.0, -34.6), 1.6)
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
    # the threshold under the doorway and the passage floor, as one walking surface
    _tread(s, "PassageTread", (8.6, 12.4), (-41.4, -37.0), 1.6)
    s.box("PassageWallWest", (8.5, 3.0, -39.3), (0.2, 2.8, 4.2), "brick")
    s.box("PassageWallEast", (12.5, 3.0, -39.3), (0.2, 2.8, 4.2), "brick")
    s.box("PassageCeiling", (10.5, 4.5, -39.3), (4.2, 0.2, 4.2), "concrete", None, False)
    s.box("PassageBack", (10.5, 3.0, -41.5), (4.2, 2.8, 0.2), "metal")
    s.box("PassageLight", (10.5, 2.7, -41.38), (1.4, 2.2, 0.04), "dusk", None, False)

    s.interactables = [
        {"name": "SchoolWallLook", "pos": (-9.5, 1.2, 7.4), "id": "street_school_wall",
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
        {"name": "ReturnPlateLook", "pos": (-10.39, 1.43, -10.8), "id": "street_return_plate",
         "inspection": "street_return_plate", "radius": 1.45,
         "outline": ("SchoolWall/StageReturnPlate/Case",)},
        {"name": "ReceiptSlotLook", "pos": (-10.37, 1.02, -24.7), "id": "street_receipt_slot",
         "inspection": "street_receipt_slot", "radius": 1.3,
         "outline": ("SchoolWallDado/StageReceiptSlot/Housing",)},
    ]
    s.exits = [
        # Back in through the side door, to the front yard. Same id as when this was the
        # teaching block's own door: saves and the journal know the street's way back by it.
        {"name": "BackToSchool", "pos": (-10.4, 0.9, sum(STREET_DOOR_Z) / 2), "id": "street_back_to_school",
         "prompt_key": "prompt.back_to_school", "radius": 1.25,
         "support": ("../../SideDoor", "../../GatePierSouth", "../../SideDoorPier"),
         "outline": ("SideDoor/StageDoor/Frame", "SideDoor/StageDoor/Bars"),
         "scene": "res://scenes/locations/front_yard/front_yard.tscn", "spawn": "FromStreet",
         "id_dest": "front_yard"},
        # The anchor stands in the doorway at the head of the stair, so a click on the stair
        # walks the player up it and through the door instead of stopping at the bottom.
        {"name": "ToResidential", "pos": (10.5, 2.5, -36.6), "id": "street_to_residential",
         "prompt_key": "prompt.stairs_up", "radius": 1.5,
         "support": tuple(f"../../{name}" for name in street_steps) + (
             "../../StairRamp", "../../StairLanding", "../../StairLandingSurface",
         ),
         "outline": tuple(street_steps) + ("StairLanding", "DoorwayLintel", "DoorwayJambWest",
                                           "DoorwayJambEast", "PassageLight"),
         "scene": "res://scenes/locations/residential/residential.tscn", "spawn": "FromStreet",
         "id_dest": "residential"},
    ]
    # `FromCorridor` is outside the side door now; it keeps the name the route used to give it,
    # because saves taken in the street name it.
    s.spawns = [("FromCorridor", (-7.4, 0, 15.2)), ("FromResidential", (10.5, 1.6, -35.4))]
    # The painted distance keeps going, but neither the asphalt nor the pavements
    # do. A low works barrier makes the playable southern edge physical and legible.
    s.box("SouthWorksBarrier", (0, 0.53, 19.79), (34, 1.06, 0.28), "concrete", ["camera_occluder"])
    s.box("SouthWorksCap", (0, 1.085, 19.79), (34, 0.12, 0.31), "metal", body=False)
    for i in range(8):
        s.box(f"SouthWorksJoint{i}", (-14.7+4.2*i, 0.53, 19.647), (.055, .90, .028), "metal", body=False)
    return s


def _school_wall(s, x, span, face):
    """The school wall along z at `x`, with the gate in it (docs/GLOSSARY.md, 校门).

    North to south: the wall, the gate's north pier, the retractable gate (伸缩门, shut: one
    collider the height of its lattice), the south pier, the side door (小门, shut until it
    is used as an exit: its leaf is the collider), the door's pier, and the wall again. The
    stage pass hides the gate's and the door's graybox and draws them (build_stage_art.py).
    `face` is +1 when the side the player walks is east of the wall, -1 when west.
    Everything is a camera occluder, so the stage pieces hung on it fade with it."""
    occ = ["camera_occluder"]
    g0, g1 = STREET_GATE_Z
    d0, d1 = STREET_DOOR_Z
    h, p = SCHOOL_WALL_H, GATE_PIER
    north = (span[0], g0 - p)
    south = (d1 + p, span[1])
    s.box("SchoolWall", (x, h / 2, sum(north) / 2), (0.3, h, north[1] - north[0]), "wall", occ)
    s.box("GatePierNorth", (x, (h + 0.3) / 2, g0 - p / 2), (p, h + 0.3, p), "wall", occ)
    s.box("RetractableGate", (x, GATE_HEIGHT / 2, (g0 + g1) / 2), (0.3, GATE_HEIGHT, g1 - g0), "metal", occ)
    s.box("GatePierSouth", (x, (h + 0.3) / 2, (g1 + d0) / 2), (p, h + 0.3, d0 - g1), "wall", occ)
    s.box("SideDoor", (x, DOOR_HEIGHT / 2, (d0 + d1) / 2), (0.1, DOOR_HEIGHT, d1 - d0), "metal", occ)
    s.box("SideDoorPier", (x, (h + 0.3) / 2, d1 + p / 2), (p, h + 0.3, p), "wall", occ)
    s.box("SchoolWallSouth", (x, h / 2, sum(south) / 2), (0.3, h, south[1] - south[0]), "wall", occ)
    # The lintel over the side door, which keeps it a door and not a gap. Its collider is on
    # the fade-only layer: nothing walks into it or clicks on it, but the camera occluder fader
    # finds it, so it fades with the wall when the camera looks through the gate at the player.
    # It is as wide as its coping (build_stage_art.py), so a sight line that crosses the
    # coping crosses the collider too.
    s.box("SideDoorLintel", (x, h + 0.05, (d0 + d1) / 2), (0.5, 0.5, d1 - d0 + 0.04), "wall", occ, True,
          FADE_ONLY_LAYER)


def _teaching_front(s):
    """The teaching block's front with the glass entrance, as the front yard sees it.

    This is the street's old west side, moved here unchanged: the long front north of the
    entrance, the return round the recess with the glass doors, and now the front south of it
    too. Its numbers are the ones the corridor's door was aligned to."""
    occ = ["camera_occluder"]
    z_school = sum(STREET_SCHOOL_Z) / 2
    length = STREET_SCHOOL_Z[1] - STREET_SCHOOL_Z[0]
    s.box("SchoolBlock", (-16, 6.5, z_school), (10, 13, length), "wall", occ)
    s.box("SchoolPlinth", (-16, 0.6, z_school), (10.2, 1.2, length), "concrete")
    z_south = sum(SCHOOL_SOUTH_Z) / 2
    south = SCHOOL_SOUTH_Z[1] - SCHOOL_SOUTH_Z[0]
    s.box("SchoolBlockSouth", (-16, 6.5, z_south), (10, 13, south), "wall", occ)
    s.box("SchoolPlinthSouth", (-16, 0.6, z_south), (10.2, 1.2, south), "concrete")
    # Keep a shallow, walkable recess behind the shared glass entrance instead
    # of putting a doorway over the side of the solid school block.
    s.box("SchoolEntryReturn", (-15.9, 5.4, 16.35), (7.8, 10.8, 7.3), "wall", occ)
    s.box("SchoolEntryEnd", (-11.45, 1.49, 19.22), (1.66, 2.68, 0.20), "wall", occ)
    s.box("SchoolEntryMat", (-10.79, 0.15, 15.8), (1.46, 0.025, 3.04), "metal", None, False)
    s.props.append(("SchoolGlassEntrance", "res://scenes/environment/props/teaching_block_entrance.tscn",
                    (-10.62, 0.15, 15.8), 90))


def build_front_yard():
    """The front yard (前操场): out of the teaching block's glass doors onto bare dirt.

    The owner's picture: no road outside the school, a dirt playground either side, dead
    trees, and the school gate - a parking-lot retractable gate, shut, and beside it a door
    one person wide with a card reader just inside it. The street starts past that door.
    The ground, the trees, the gate and the reader are drawn by the stage pass
    (build_stage_art.py, FRONT_YARD); here are the walk, the walls and the routes."""
    s = Scene("FrontYard", "front_yard")
    s.env = {
        'sky': 'Color(0.243, 0.196, 0.176, 1)',
        'ambient': 'Color(0.52, 0.43, 0.36, 1)',
        'energy': '1.05',
        'fog': 'Color(0.34, 0.27, 0.22, 1)',
        'fog_density': '0.004',
        'saturation': '0.85',
    }
    s.sun = {'rotation': (-14, 38, 0), 'color': 'Color(1, 0.72, 0.5, 1)', 'energy': 2.1}
    s.ambience = {'volume': -18.0, 'target': -26.0}
    z0, z1 = FRONT_YARD_Z
    x0, x1 = -11.0, YARD_WALL_X + 0.15
    occ = ["camera_occluder"]
    # the dirt, and a concrete apron along the block's foot and into the entrance's recess
    s.box("YardGround", ((x0 + x1) / 2, -0.1, (z0 + z1) / 2), (x1 - x0, 0.2, z1 - z0), "soil")
    s.box("SchoolApron", (-10.3, 0.075, (z0 + z1) / 2), (1.4, 0.15, z1 - z0), "concrete")
    s.box("PavementSchoolEntry", (-11.5, 0.075, 16.35), (1.0, 0.15, 7.3), "concrete")
    _teaching_front(s)
    # North and south, a low railing (栏杆): the sports ground goes on past it, dirt and dead
    # trees into the haze, so the block has playground on both sides. East, the school wall
    # with the gate in it.
    for name, z in (("NorthRail", z0 + 0.15), ("SouthRail", z1 - 0.15)):
        s.box(name, ((x0 + x1) / 2, 0.6, z), (x1 - x0, 1.2, 0.1), "metal", occ)
    _school_wall(s, YARD_WALL_X, (z0 + 0.3, z1 - 0.3), -1)
    # the dead trees: a trunk to walk round, and a fader box round the crown (layer 8 only)
    bw, bh = FRONT_YARD_TREE_BOX
    for i, (x, z, _variant, _yaw) in enumerate(FRONT_YARD_TREES):
        s.box(f"DeadTree{i}", (x, bh / 2 - 0.1, z), (bw, bh, bw), "soil", occ, True, FADE_ONLY_LAYER)
        s.box(f"DeadTree{i}Trunk", (x, 1.0, z), (0.42, 2.0, 0.42), "soil")
    d_mid = sum(STREET_DOOR_Z) / 2
    g_mid = sum(STREET_GATE_Z) / 2
    tx = FRONT_YARD_TREES[0][0]

    s.interactables = [
        # placeholders until the owner writes them (data/inspections/*/front_yard.json)
        {"name": "CardReaderLook", "pos": (14.62, 1.3, STREET_DOOR_Z[1] + GATE_PIER / 2), "id": "front_yard_card_reader",
         "inspection": "front_yard_card_reader", "radius": 0.95,
         "support": ("../../SideDoorPier",), "outline": ("SideDoorPier/StageCardReader/Body",)},
        {"name": "GateLook", "pos": (14.55, 1.0, g_mid - 1.2), "id": "front_yard_gate",
         "inspection": "front_yard_gate", "radius": 1.4,
         "support": ("../../RetractableGate",), "outline": ("RetractableGate/StageGate/Head",)},
        {"name": "DeadTreeLook", "pos": (tx + 0.45, 1.2, FRONT_YARD_TREES[0][1] + 0.45), "id": "front_yard_dead_tree",
         "inspection": "front_yard_dead_tree", "radius": 1.3,
         "support": ("../../DeadTree0Trunk",), "outline": ("DeadTree0/StageTree/Trunk",)},
    ]
    s.exits = [
        {"name": "BackInside", "pos": (-9.6, 0.9, 15.8), "id": "front_yard_back_inside",
         "prompt_key": "prompt.back_inside", "radius": 1.25,
         "support": ("../../SchoolGlassEntrance/Left", "../../SchoolGlassEntrance/Right",
                     "../../SchoolGlassEntrance/Header"),
         "outline": ("SchoolGlassEntrance/Left/Stile", "SchoolGlassEntrance/Right/Stile",
                     "SchoolGlassEntrance/Header/Shoe"),
         "scene": "res://scenes/locations/corridor/corridor.tscn", "spawn": "FromTeachingEntrance",
         "id_dest": "corridor"},
        # Out through the side door; nobody has to swipe (the reader is only to look at).
        # Close to the leaf, so the camera's line to it crosses the door and not the pier
        {"name": "ToStreet", "pos": (14.75, 0.9, d_mid), "id": "front_yard_to_street",
         "prompt_key": "prompt.out_gate", "radius": 1.25,
         "support": ("../../SideDoor", "../../GatePierSouth", "../../SideDoorPier"),
         "outline": ("SideDoor/StageDoor/Frame", "SideDoor/StageDoor/Bars"),
         "scene": "res://scenes/locations/street/street.tscn", "spawn": "FromCorridor",
         "id_dest": "street"},
    ]
    s.spawns = [("FromCorridor", (-5.5, 0, 13.5)), ("FromStreet", (12.0, 0, d_mid))]
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
    s.box("StairLanding", (-9.9, 0.9, -13.55), (2.2, 1.8, 2.4), "concrete", body=False)
    _landing_surface(s, "StairLandingSurface", (-11.0, -8.8), (-14.75, -12.65), 1.8)
    _tread(s, "StairLandingTread", (-11.0, -8.8), (-14.75, -12.35), 1.8)
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
         "support": tuple(f"../../{name}" for name in street_steps) + (
             "../../StreetStairRamp", "../../StreetGatePostNorth", "../../StreetGatePostSouth",
         ),
         "outline": tuple(street_steps) + ("StreetGatePostNorth", "StreetGatePostSouth",
                                           "StreetGateLintel", "StreetGateSign"),
         "scene": "res://scenes/locations/street/street.tscn", "spawn": "FromResidential",
         "id_dest": "street"},
        {"name": "AlleyEnd", "pos": (6.0, 0.9, -34.6), "id": "res_alley_end",
         "prompt_key": "prompt.milestone", "radius": 1.6,
         "support": ("../../AlleyBackPierWest", "../../AlleyBackPierEast", "../../AlleyBeyondLight"),
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
        {"name": "ReturnPlateLook", "pos": (-3.12, 1.43, -18.55), "id": "alley_return_plate",
         "inspection": "alley_return_plate", "radius": 1.4,
         "outline": ("WallWest/StageReturnPlate/Case",)},
        {"name": "TrolleyGuideLook", "pos": (-3.12, 0.76, 5.6), "id": "alley_trolley_guide",
         "inspection": "alley_trolley_guide", "radius": 1.25,
         "outline": ("WallWest/StageTrolleyGuide/Rail",)},
    ]
    s.exits = [
        {"name": "BackToCourtyard", "pos": (0.0, 0.9, 12.5), "id": "alley_back_to_courtyard",
         "prompt_key": "prompt.back_to_street", "radius": 1.4,
         "support": ("../../MouthPierWest", "../../MouthPierEast", "../../MouthCourtyardLight"),
         "outline": ("MouthPierWest", "MouthPierEast", "MouthLintel", "MouthCourtyardLight"),
         "scene": "res://scenes/locations/residential/residential.tscn", "spawn": "FromAlley",
         "id_dest": "residential"},
        {"name": "ToPlayground", "pos": (0.0, 0.9, -21.6), "id": "alley_to_playground",
         "prompt_key": "prompt.alley_gate", "radius": 1.6,
         "support": ("../../GatePostWest", "../../GatePostEast"),
         "outline": ("GateLeaf", "GatePostWest", "GatePostEast"),
         "scene": "res://scenes/locations/playground/playground.tscn", "spawn": "FromAlley",
         "id_dest": "playground"},
    ]
    s.spawns = [("FromCourtyard", (0.0, 0, 10.5)), ("FromPlayground", (0.0, 0, -20.0))]
    return s


# Round 20 layout: the shed in the north-east, against the fence before the teaching block,
# beside the container; its tyres by its footings; the cactus plot where it used to stand.
# x leaves 0.6 m clear of the container's closed rear end, where the roof drop lands
# (`RoofWayDown.HIDE`, (8.4, 0, -15.3) in the yard).
SHED_CENTRE = (4.8, 1.5, -16.9)
TYRES = (-2.4, -15.3)
CACTUS_PLOT = (-16.0, 0.0, -4.0)
# The razor-wire fences on the open edges (round 21): (body centre, body size). The west
# one runs from the school plinth to the building site's north side (z 7); the east one
# fills the gap between the flats' south face (z 18) and the south fence. Along the site
# (z 7 to the south fence) the hoarding is the fence and the edge is a thin invisible body:
# it keeps clear of the gate and climb anchors at x -22.6, and with nothing drawn on it it
# hides neither the gate nor the sand pile from the pointer (interaction_controller.gd).
RAZOR_WIRE_WEST = ((-22.75, 1.4, -6.35), (0.6, 2.8, 26.7))
SITE_EDGE_WEST = ((-22.95, 1.4, 13.3), (0.2, 2.8, 12.6))
RAZOR_WIRE_EAST = ((22.75, 1.4, 18.76), (0.6, 2.8, 1.52))


def build_playground(for_courtyard_view: bool = False):
    """The open yard.

    Deliberately not a corridor and not a circuit: it is a rectangle you can walk
    across in any direction, with four things worth stopping for placed on three
    different sides so the player has to choose an order. The middle is left
    empty on purpose: that is the room later events and NPCs need.
    """
    s = Scene("Playground", "playground")
    container_origin = (12, 0, -15.5)
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
    # east side: the flats (the hedge that hides what is under the shed moved with it, round 20)
    s.box("EstateBlockEast", (24, 6.0, -2), (8, 12, 40), "brick", ["camera_occluder"])
    # Round 21: the yard's open edges, closed. The owner could walk off the west side (and
    # the gap between the east flats and the south fence): a prison fence of chain-link
    # under concertina razor wire, with a second coil along its foot on the yard side,
    # stands on each. The art pass hangs the posts, mesh and coils on these bodies and hides
    # their boxes; the body is as deep as the foot coil. The estate gate keeps its way out
    # (the alley exit), but a threshold stops a body walking through it off the ground.
    s.box("RazorWireWest", RAZOR_WIRE_WEST[0], RAZOR_WIRE_WEST[1], "metal")
    s.box("RazorWireEast", RAZOR_WIRE_EAST[0], RAZOR_WIRE_EAST[1], "metal")
    s.box("SiteEdgeWest", SITE_EDGE_WEST[0], SITE_EDGE_WEST[1], "metal")
    s.box("AlleyThreshold", (0.0, 1.1, 19.6), (3.8, 2.2, 0.16), "metal")

    # the two hoops
    for name, x in (("HoopNear", -8.0), ("HoopFar", 8.0)):
        z = 7.5 if name == "HoopNear" else -11.5
        s.box(f"{name}Pole", (x, 1.6, z), (0.18, 3.2, 0.18), "metal")
        s.box(f"{name}Board", (x, 3.05, z), (1.8, 1.1, 0.08), "paper", None, False)
        s.box(f"{name}Rim", (x, 2.6, z - 0.3), (0.05, 0.05, 0.45), "metal")
        s.box(f"{name}Footing", (x, 0.1, z), (1.2, 0.2, 1.2), "concrete")

    # The equipment shed, round 20: moved from the west side into the north-east of the yard,
    # its back against the fence in front of the teaching block and its east end tucked in
    # beside the blue container (the corner itself is the container's, with its cabin doors
    # and ladder, so the shed takes the run of fence just west of it). The door now faces
    # south, across the court. Its old place on the west side holds the cactus plot.
    s.box("ShedBody", SHED_CENTRE, (6.0, 3.0, 3.1), "wall", ["camera_occluder"])
    # Both views use the actual roof slab. The yard art pass adds seams and a gutter
    # to it and replaces the distant door, glazing and sign with detailed wall trim.
    s.box("ShedRoof", (SHED_CENTRE[0], 3.1, SHED_CENTRE[2]), (6.4, 0.2, 3.5), "metal", None, False)
    if for_courtyard_view:
        face = SHED_CENTRE[2] + 1.55
        s.box("ShedDoor", (SHED_CENTRE[0], 1.1, face + 0.06), (1.1, 2.2, 0.12), "hedge", None, False)
        s.box("ShedWindow", (SHED_CENTRE[0] + 1.85, 1.9, face + 0.05), (1.2, 0.8, 0.1), "glass", None, False)
        s.box("ShedSheet", (SHED_CENTRE[0] + 1.85, 1.9, face + 0.1), (0.9, 0.5, 0.08), "paper", None, False)
    # two footings off the shed's west end, and the gap is only on the left one
    s.box("ShedFootingWest", (-1.3, 0.2, -16.4), (1.4, 0.4, 1.4), "concrete")
    s.box("ShedFootingEast", (1.05, 0.3, -16.4), (1.4, 0.6, 1.4), "concrete")
    s.box("ShedHedge", (-0.4, 0.55, -17.9), (2.6, 1.1, 1.4), "hedge", None, False)
    s.box("PaleUnderHedge", (0.2, 0.45, -17.9), (0.9, 0.05, 0.16), "paper", None, False)
    s.box("PingPongBall", (-0.15, 0.16, -16.4), (0.06, 0.06, 0.06), "paper", None, False)

    # climbing frame on the east side
    for i, z in enumerate((7.0, 9.0, 11.0)):
        s.box(f"FramePost_{i}", (18.0, 1.4, z), (0.14, 2.8, 0.14), "metal")
    for i, y in enumerate((0.9, 1.4, 1.9, 2.4)):
        s.box(f"FrameRung_{i}", (18.0, y, 9.0), (0.12, 0.12, 4.0), "metal", None, False)
    s.box("FrameTopBar", (18.0, 2.85, 9.0), (0.14, 0.14, 4.2), "metal", None, False)

    # tyres stacked by the shed's footings: the yard's older gym, painted over twice
    for i, y in enumerate((0.12, 0.36, 0.6)):
        s.box(f"TyreStack_{i}", (TYRES[0], y, TYRES[1]), (1.0, 0.22, 0.42), "metal", None, False)
    s.box("TyreLoose", (TYRES[0] + 1.1, 0.12, TYRES[1] + 0.9), (0.92, 0.22, 0.4), "metal", None, False)

    # In the distant teaching-wing view keep the same cheap three-mesh silhouette.
    # The playable yard instances the full shell at the same footprint and roof height.
    if for_courtyard_view:
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
    # Two of them sit on the front edge of the shed roof, now that the shed has the fence.
    for i, (x, y, z) in enumerate(((4.6, 3.26, -15.3), (5.5, 3.26, -15.25), (-3.0, 1.75, -18.5))):
        s.box(f"Bird_{i}", (x, y, z), (0.16, 0.12, 0.22), "metal", None, False)
    s.box("BirdWire", (2.0, 2.9, -18.55), (16.0, 0.02, 0.02), "metal", None, False)

    # Keep the standpipe solid. The art pass supplies a round pipe, bibcock and grating.
    s.box("TapPost", (-6.0, 0.9, 14.0), (0.16, 1.8, 0.16), "metal")
    s.box("TreeTrunk", (20.0, 2.0, 15.0), (0.5, 4.0, 0.5), "soil")
    s.box("TreeCrown", (20.0, 4.6, 15.0), (3.6, 2.2, 3.6), "hedge", None, False)

    # The wooden bench faces the court. The split film rests on the existing
    # 0.51 m slats. It does not need the old backpack's collider inside the bench.
    s.props = [
        ("YardBench", "res://scenes/environment/props/playground_bench.tscn", (11.0, 0.0, 3.2), -90.0),
    ]
    if not for_courtyard_view:
        s.props.extend([
            ("YardNoodleWrapper", "res://scenes/environment/props/playground_art/noodle_wrapper.tscn",
             (10.99, 0.51, 3.74), -14.0),
            ("ContainerBody", "res://scenes/environment/props/playground_art/container.tscn", container_origin, 0),
            # Same origin, separate from the shell so occlusion fading never dissolves the resident.
            ("RoofEncounter", "res://scenes/locations/playground/roof_encounter.tscn", container_origin, 0),
            # Round 20: where the shed stood, a square of soil let into the concrete, a giant
            # saguaro in it and a girl skipping beside it (playground_art/source/cactus_plot.py).
            ("CactusPlot", "res://scenes/environment/props/playground_art/cactus_plot.tscn", CACTUS_PLOT, 0),
        ])

    s.interactables = [
        {"name": "HoopLook", "pos": (-8.0, 1.4, 8.8), "id": "pg_hoop_near",
         "inspection": "pg_hoop", "radius": 1.5,
         "outline": ("HoopNearPole", "HoopNearBoard", "HoopNearRim", "PlaygroundArt/Equipment/HoopNearRing")},
        {"name": "CourtLook", "pos": (0.0, 0.9, 2.0), "id": "pg_court_middle",
         "inspection": "pg_court", "radius": 1.8,
         # The painted court markings: what "the court" is, as opposed to the ground it is on.
         "outline": ("PlaygroundArt/Court",)},
        {"name": "BenchLook", "pos": (10.2, 1.0, 3.2), "id": "pg_bench_look",
         "inspection": "pg_bench", "radius": 1.4,
         "shot": "res://assets/camera/shots/playground_bench.tres",
         "outline": ("YardBench", "YardNoodleWrapper/Film")},
        {"name": "FrameLook", "pos": (17.0, 1.4, 9.0), "id": "pg_frame_look",
         "inspection": "pg_frame", "radius": 1.5,
         "outline": tuple(f"FramePost_{i}" for i in range(3)) + tuple(f"FrameRung_{i}" for i in range(4))
                    + ("FrameTopBar",)},
        {"name": "ShedLook", "pos": (SHED_CENTRE[0], 1.1, SHED_CENTRE[2] + 2.35), "id": "pg_shed_door",
         "route": "pg_shed", "prompt": "Try the shed", "radius": 1.5,
         "shot": "res://assets/camera/shots/playground_shed.tres",
         "outline": ("ShedBody/Facade/Door", "ShedBody/Facade/Hasp", "ShedBody/Facade/Padlock")},
        {"name": "BallLook", "pos": (0.05, 0.8, -15.7), "id": "pg_ball_look",
         "route": "pg_ball", "prompt": "The ball under the shed", "radius": 1.4,
         "outline": ("PingPongBall",)},
        {"name": "TapLook", "pos": (-5.58, 1.08, 14.0), "id": "pg_tap",
         "inspection": "pg_tap", "radius": 1.3,
         "script": "res://scenes/locations/playground/yard_tap.gd",
         "shot": "res://assets/camera/shots/playground_tap.tres",
         "outline": ("PlaygroundArt/TapDetail/Standpipe", "PlaygroundArt/TapDetail/Bib",
                     "PlaygroundArt/TapDetail/Wheel/Rim", "PlaygroundArt/TapDetail/Cap")},
        {"name": "ContainerLook", "pos": (15.25, 1.05, -15.5), "id": "pg_container_look",
         "inspection": "pg_container", "radius": 1.4,
         "shot": "res://assets/camera/shots/container_cabin.tres",
         "outline": ("ContainerBody/EndHeader", "ContainerBody/DoorNorth/Panel", "ContainerBody/DoorSouth/Panel")},
        {"name": "CabinPapersLook", "pos": (14.21, 0.32, -14.91), "id": "pg_cabin_papers_look",
         "inspection": "pg_cabin_papers", "radius": 0.95,
         "shot": "res://assets/camera/shots/container_papers.tres",
         "outline": ("ContainerBody/Cabin/Papers/ClippedPage/Paper",)},
        {"name": "TyreLook", "pos": (TYRES[0] + 0.6, 1.1, TYRES[1] + 0.3), "id": "pg_tyre_look",
         "inspection": "pg_tyres", "radius": 1.4,
         # The ring tyres the art pass adds; the graybox stack they replace is hidden, and
         # hidden meshes are skipped, so listing both keeps the outline right either way.
         "outline": tuple(f"PlaygroundArt/Equipment/Tyre_{i}" for i in range(4))
                    + ("PlaygroundArt/Equipment/TyreLoose",)},
        # The building under construction stands too tall for the default framing; this
        # shot backs the camera off and lifts its aim until the whole shell is in view.
        {"name": "SiteLook", "pos": (-22.6, 1.0, 13.2), "id": "pg_site_look",
         "inspection": "pg_site", "radius": 1.4,
         "shot": "res://assets/camera/shots/building_site.tres",
         "outline": ("PlaygroundArt/BuildingSite/Gate/LeafNorth/Frame",
                     "PlaygroundArt/BuildingSite/Gate/LeafSouth/Frame")},
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
        # The building site (round 11). The gate is padlocked: until the key from inside
        # the building is held, `site_gate.gd` keeps this exit off and `SiteLook` answers
        # at the same spot. The south sand pile is the way in without it, over the
        # hoarding; from inside there is no climbing back, so the porch door wants the key.
        {"name": "SiteGate", "pos": (-22.6, 0.9, 13.2), "id": "pg_site_gate",
         "script": "res://scenes/locations/playground/site_gate.gd",
         "prompt_key": "prompt.site_gate", "radius": 1.8,
         "outline": ("PlaygroundArt/BuildingSite/Gate/LeafNorth/Frame",
                     "PlaygroundArt/BuildingSite/Gate/LeafSouth/Frame"),
         "scene": "res://scenes/locations/site_interior/site_interior.tscn", "spawn": "FromPorch",
         "id_dest": "site_interior", "required_flag": "site_gate_key", "blocked_inspection": "pg_site"},
        {"name": "SiteClimb", "pos": (-22.7, 0.9, 17.05), "id": "pg_site_climb",
         "prompt_key": "prompt.site_climb", "radius": 1.6,
         "outline": ("PlaygroundArt/BuildingSite/Sand/PileSouth/Body",),
         "scene": "res://scenes/locations/site_interior/site_interior.tscn", "spawn": "FromPorch",
         "id_dest": "site_interior"},
        # The container yard (round 13), through the chain-link behind the blue container.
        # The bent-back sheet it outlines is added by the art pass (build_playground_art.py).
        {"name": "ToContainerYard", "pos": (13.0, 0.9, -18.2), "id": "pg_container_yard",
         "prompt_key": "prompt.container_yard", "radius": 1.6, "outline": ("FenceRunNorth/YardGapFlap",),
         "scene": "res://scenes/locations/container_yard/container_yard.tscn", "spawn": "FromPlayground",
         "id_dest": "container_yard"},
    ]
    s.spawns = [
        ("FromAlley", (0.0, 0, 16.0)),
        # The walkway's end door: this is the intended way into the yard, so the
        # player arrives from the school side rather than from the estate gate.
        ("FromCorridor", (-3.0, 0, -17.6)),
        # Arrival from classroom window curtain fall: lands on top of the blue container.
        ("FromSchool", (12.0, 2.6, -15.5)),
        # Out of the building site's gate, on the yard side of it.
        ("FromSite", (-21.6, 0, 13.2)),
        # Back from the container yard, behind the blue container.
        ("FromContainerYard", (13.0, 0, -17.6)),
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
    `base`, not a floating slab: seen from the side, a flight of slabs reads as a shelf. The
    block remains in the navigation bake but uses the navigation-only layer; the player rides
    `_ramp` instead of switching contact surfaces between the slope and each riser.
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
        s.box(name, pos, size, mat, collision_layer=NAVIGATION_ONLY_LAYER)
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


def _tread(s, name, x_range, z_range, top):
    """An invisible 10 cm slab whose top is the walking surface of a solid box under it.

    `LocationNavigation._add_shape` hands Recast each box's faces in an order that makes
    the box's underside, not its top, the face that points up. A box therefore counts as
    floor only when it is thinner than one climb voxel (0.25 m), so that its top and bottom
    land in the same span: the road, the pavements, the kerbs and the slab floors do; a
    landing 1.6 m tall does not, and neither does anything standing on it. Rather than
    change what every existing room bakes, a solid box someone has to walk on gets a thin
    slab at its top (and a flight gets a thin slope, `_ramp`). The body stands on the box
    exactly as before; only the bake sees the difference.
    """
    thickness = 0.1
    pos = (round((x_range[0] + x_range[1]) / 2.0, 4), round(top - thickness / 2.0, 4),
           round((z_range[0] + z_range[1]) / 2.0, 4))
    size = (round(x_range[1] - x_range[0], 3), thickness, round(z_range[1] - z_range[0], 3))
    s.ramp(name, pos, size, (0, 0, 0), BAKE_ONLY_LAYER)


def _landing_surface(s, name, x_range, z_range, top):
    """A thin physical top at a landing, without the tall plinth's blocking front face.

    The visual plinth remains a mesh. This 5 cm collider is in the player's layer only,
    inset behind the stair-side lip so the capsule reaches landing height before touching
    its edge. Navigation uses `_tread`, and interaction rays do not see the support surface.
    """
    thickness = 0.05
    pos = (round((x_range[0] + x_range[1]) / 2.0, 4), round(top - thickness / 2.0, 4),
           round((z_range[0] + z_range[1]) / 2.0, 4))
    size = (round(x_range[1] - x_range[0], 3), thickness, round(z_range[1] - z_range[0], 3))
    s.ramp(name, pos, size, (0, 0, 0), PLAYER_ONLY_LAYER)


def _ramp(s, name, steps, rise, run, x_range, z_range, axis, direction, start, base):
    """An invisible walking slope over a flight built by `_stair`, through its nosings.

    The player collides with this continuous ramp on the world layer; the visible stair
    blocks are navigation-only, so the body never alternates between the ramp and individual
    treads. Both layers are retained in the navigation bake. The bake only treats a collision
    box as floor when it is thin: see `_tread`. A solid step is not floor, so a flight of
    them is drawn but cannot be routed up, and an exit at its head sits metres off the mesh.
    A thin slope the bake sees is the answer. Its top surface runs through the front edge of
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
    s.ramp(name, pos, size, rotation, collision_layer=1)


def write(scene, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(scene.emit())
    print("wrote", path.replace(ROOT + "/", ""))


BUILDERS = {
    "front_yard": build_front_yard,
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
