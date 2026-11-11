# Character animation

Two rigged characters exist in this repository, neither is wired into the game yet, and
their clips are built in code. This page says what runs, what the first attempt got wrong,
and how to do the same thing by hand in the Godot editor.

## What runs today

| | Q | Protagonist |
|---|---|---|
| Model | `scenes/dev/animation_retarget_test/q_rigged.glb` | `scenes/dev/animation_retarget_test/protagonist_retarget_ready.glb` |
| Source | `art/character_rigging/q/q_rigged_working.blend` | `art/character_rigging/protagonist_retarget/protagonist_retarget_ready.blend` |
| Joints | 16 | 21 |
| Bone naming | `Root, Spine, Neck, Head, UpperArm.L, LowerArm.L, Hand.L, Thigh.L, Shin.L, Foot.L, …` | `Root, Hips, Spine, Chest, UpperChest, Neck, Head, LeftShoulder, LeftUpperArm, LeftLowerArm, LeftHand, LeftUpperLeg, LeftLowerLeg, LeftFoot, …` |
| Clips | idle, walk, wave, talk | idle, walk, wave, talk, + 42 retargeted from the library |

`scripts/actors/character_animation.gd` authors those four clips against *canonical* names
(`hips`, `spine`, `upper_arm.L`, `shin.R`, …) and resolves them against whichever rig it is
handed. A canonical bone a rig does not have is reported and its track left out; a track is
never written for a bone that is not there, because an `Animation` whose track path names a
missing bone plays nothing and prints nothing.

- **See it:** open `scenes/dev/animation_retarget_test/animation_preview.tscn` and press
  **F6**. Keys **1** idle, **2** walk, **3** wave, **4** talk, **space** pause, **R** re-bind
  after re-importing a model.
- **Check it:** `tests/character_animation_test.gd` runs headless in CI (`character_animation`
  in the check list). It seeks each clip and reads the skeleton's bone poses, so "the clip
  moves the character" is measured, not assumed.
- **The animation library, retargeted.** `protagonist_ual.res` holds the Universal Animation
  Library's 42 clips rewritten onto the protagonist's bones — see below. Open
  `scenes/dev/animation_retarget_test/protagonist_ual_preview.tscn`, select
  `Protagonist/UalPlayer`, and scrub any `ual/…` animation in the Animation panel: no engine
  trickery at play time, just animation data with this character's bone names on it.
- **Neither model is used by the game.** `assets/models/q/q.glb` has no skeleton at all and
  `assets/models/protagonist/protagonist.glb` has the older 16-bone rig; both are what the
  game loads, unchanged. Swapping them is the next step and it is deliberate (see the end).

## What the first attempt got wrong

The `protagonist retarget test` branch did the hard part — it rigged Q and it produced a
humanoid skeleton for the protagonist — and then stopped one step short, in five ways.

**1. Two rigs, two naming conventions, and no map between them.** Q was rigged with
`UpperArm.L`, `Thigh.L`, `Shin.L` — the production protagonist's names, which is right. The
protagonist was *retargeted* to `LeftUpperArm`, `LeftUpperLeg`, `LeftLowerLeg` — a
Mixamo-style set. So the two characters cannot play one clip file: every bone in every clip
would have to be renamed per character. Its own report says the same thing in a warning:
"No animation is retargeted by this script."

**2. The names in Blender are not the names in the scene.** Q's neck is `Neck`; the
protagonist's neck bone is `Neck_2`. Godot renames a glTF node whose name is already taken to
`Name_2`, and the protagonist export contains more than one node called `Neck` — Blender is
happy with that, glTF is happy with that, Godot is not. So a per-character mapping written
from the Blender outliner is wrong for the bone that happened to be renamed, and a retarget
done by matching names in Blender (which is the obvious way to do it) breaks on exactly one
bone, silently. `CharacterAnimation` tries the plain name first and the `_2` form second for
this reason, and `describe()` prints which bone each canonical name landed on.

**3. The animation library used a third convention and was never mapped.** Quaternius'
Universal Animation Library names its 65 joints `upperarm_l`, `calf_l`, `spine_01`,
`clavicle_l`, `ball_leaf_l`. That is a third spelling of the same skeleton, and nothing
translated it. The library was imported and connected to an `AnimationPlayer`, but no clip
named a bone the character has.

**4. The library was attached from inside the game's main scene, with nothing to attach it
to.** `scenes/main/main.tscn` gained `[ext_resource type="AnimationLibrary" …
path="…/UAL1_Standard.glb"]` and a `libraries = {"…": ExtResource(…)}` on a `Player`. The
resource type was right — this engine can import a glTF as an `AnimationLibrary` — but the
import had never run, so the path resolved to nothing and the parse error took the whole main
scene down: every gameplay check failed on `[ext_resource] referenced non-existent resource`,
which pointed at the assets rather than at the import that was missing. A library's tracks are
also no closer to the character's bones for being attached; see 1–3.

**5. The experiment was put inside the game's main scene.** A retarget rig, a duplicate
protagonist model and a 7.6 MB animation library now loaded on every launch, including the
release build's playthrough capture. A dev scene is a dev scene; `scenes/dev/` is already
excluded from the export.

**6. The commit contained the editor's cache and its own machine state.** 69
`docs/screenshots/*.png.import` sidecars (screenshots are documentation, not assets), five
`*.import` sidecars for `.blend` files under `art/` (sources, and importing a `.blend` needs a
Blender install that CI does not have), a duplicate copy of the retargeted `.glb`, an
undocumented second copy of the Q `.blend`, and a `project.godot` rewritten by the editor:
its own comments gone, `[physics]`, `rendering_method`, `window/size/resizable` and
`window/size/initial_position_type` dropped, and every input action given `"device":16` or
`"device":32` — the device numbers of whatever was plugged into the machine that saved it.

The fixes are in the history: `docs/.gdignore`, `art/character_rigging/.gdignore`, the editor
rewrites reverted, one copy of each model, and the animation library deleted rather than
licensed, documented and shipped.

## The animation library, retargeted

`AnimationRetarget` pairs the two rigs through the same canonical names
`CharacterAnimation` uses — which are the humanoid profile's names, the ones the `BoneMap`s in
both `.import` sidecars are written in — and then bakes:

```
for every clip, sampled at 30 fps:
    change = source_rest_global⁻¹ · source_global        (what the library did to that bone)
    target_global = target_rest_global · change          (what this bone should do instead)
    local = parent_global⁻¹ · target_global              (what the pose actually stores)
```

Rest-relative, so a bone whose rest pose points a different way on the two rigs still lands
where the animation puts it instead of inheriting the library's twist. The two chains differ in
length — the library spends a spine over `spine_01..03`, the character over `Spine`, `Chest`,
`UpperChest`, and only two of those three pair up — so the chest chain disagrees by about 3°
while everything else agrees to within one. That is the size of the difference `_2`-suffix
matching and a three-bone spine buy you; it is also why the tolerance in the test is 5° and not
0.5°. Positions are not
copied, the library's fingers are dropped (this character has none), and `_2`-suffixed bones
are matched like any other.

The result is committed as `scenes/dev/animation_retarget_test/protagonist_ual.res` (about
1 MB). Regenerate it after changing the mapping or either model:

~~~text
godot --headless --path . --import
godot --headless --path . --script res://tools/bake_animation_retarget.gd
~~~

The `bake-animation-retarget` workflow runs exactly those two commands and commits the result,
for when there is no engine on the machine doing the editing. Dispatch it from the Actions tab;
it is deliberately not part of the check list, because a build that rewrites a tracked file on
every push is a build that fails on a dirty tree for reasons nobody reads twice.

`tests/ual_retarget_test.gd` checks the three things that can be silently wrong: the bones pair
up (19 of them, spot-checked by name), the baked clip moves the character (measured off the
skeleton), and the retarget is rest-relative — at every sampled instant the source bone's
rotation change and the target's are *the same rotation*, within half a degree. A bake that
renamed tracks without recomposing the hierarchy passes the first two and fails the third.

## Doing it by hand in the editor

The code route above is not the only one. What follows is the same job by hand, which is what
to reach for when a rig has to come from an external library.

**Before anything: confirm the model is actually rigged.** Open the `.glb`, and in the
Advanced Import Settings dialog look for a `Skeleton3D` and, under *Skeleton*, a bone list. If
there is none — Q as supplied had none — no amount of animation work will move it. The GLB's
own JSON answers the same question without a renderer (`art/character_rig_audit/README.md`).

**Option A — rename the bones so every rig agrees (what this repository does).** In Blender,
give the characters the same bone names in the same hierarchy, then export. That is why Q was
rigged to `UpperArm.L`: it matches the production protagonist, so one clip set fits both.
Cheap, and the failure mode is visible — a bone you did not rename simply does not move.

**Option B — map the names (what `CharacterAnimation` does in code).**

```gdscript
var report := CharacterAnimation.bind(model_root, animation_player)
print(CharacterAnimation.describe(report))   # resolved bones, missing bones, track counts
CharacterAnimation.play(animation_player, "walk")
```
The `AnimationPlayer` must be a **child of the model** and its `root_node` must point at the
model; track paths are `Skeleton3D:BoneName`, relative to that root. `describe()` prints what
did not resolve, which is the half of this job that is otherwise silent.

**Option C — Godot's own retargeting.** This is what the library's `.import` sidecar is
already configured for, and what `AnimationRetarget` does in code instead. In the character's
Advanced Import Settings, the
*Skeleton* section has a **Retarget** control that binds the rig to the humanoid bone profile
(`SkeletonProfileHumanoid`). Import the animation library as a scene, then in the character's
`AnimationPlayer` use *Animation → Manage Animations → Load Library* and pick the library
scene's clips. This only works when both skeletons are described by the same profile, which
is exactly the step that was skipped: a 21-joint Mixamo-style rig cannot be matched to a
65-joint UE-style library by a profile neither side declares. Map the profile on both, or
rename the bones, or do it in code.

**If a clip plays but nothing moves,** the track path is wrong. Open the Animation panel, look
at a track's name (`Skeleton3D:UpperArm.L`) and compare it with the bone list in the scene's
`Skeleton3D` node. A path naming a bone that is not there is not an error in Godot; it is
silence. The bone list in the *scene* is the truth, not the one in Blender: the production
protagonist's neck is `Neck_2` there.

**To ship it, in this order:** replace the exported model under `assets/models/` (keeping the
wrapper scene's collision, origin correction and interaction anchor), run the full check list
plus the playthrough capture, and only then add an `AnimationPlayer` and
`CharacterAnimation.bind()` to `scenes/actors/player/player.tscn` and
`scenes/actors/npc/companion.tscn`. The wrapper scene is what the game knows; the `.glb`
behind it can be swapped without touching gameplay code, and that is the reason to do it in
that order.
