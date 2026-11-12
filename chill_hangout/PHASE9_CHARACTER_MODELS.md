# Phase 9 - Quaternius character models

The procedural male/female characters were replaced by the two supplied GLBs
(`assets/characters/male_character.glb` = "Man by Quaternius", `assets/characters/female_character.glb` = "Animated Woman by Quaternius").
Only `scripts/player/character_model.gd` and `scripts/ui/character_customization.gd` changed (plus the new assets). Networking,
servers, rooms, player controller, saving, menus and every other script are untouched.

## How it works
* `CharacterModel` keeps its whole public API (`create/preset/rebuild/animate/play_emote/stop_emote/get_emote/get_right_hand_position/
  get_right_shoulder`, `emote_ended`, `step_pending`, `sit_height`, `body`, `scale`). `rebuild()` loads the GLB for `app["gender"]`
  and only re-skins / re-scales it when other options change. The appearance Dictionary and `user://character.json` are unchanged,
  so nothing is sent over the network except the same appearance data, and old saves load as before.
* The only transform applied to a GLB is a uniform scale (male 0.38, female 0.337: both GLBs are ~5 units tall) and a 180 degree turn
  (the GLBs face +Z, the game faces -Z). Meshes, UVs, skeletons, textures and materials are untouched.
* **Animation**: idle / walk / run / sit / stand come from each GLB's own clips (clip names are per model, see `RIGS`).
  The original procedural rig is kept as an invisible driver built from the real limb lengths of the GLB skeleton. All original
  crouch, emote, prop (coffee cup, HI sprite) and wave code runs on it unchanged and its joint angles are retargeted onto the GLB
  bones (`_retarget`) only while the driver is in charge (an emote's joints, crouch body/legs, main-menu wave).
* **Seat**: hips are pinned over the seat point and set to the seat height (the clips were authored for one chair height).
* **Footsteps** are emitted from the actual foot plants of whichever clip plays.

## Customization (default = the GLB exactly as supplied)
An option equal to the model's default (`AppearanceData.default_for`) leaves the original imported materials in place.
Anything else creates a duplicate material override; the imported resources are never edited.
| Option | Male GLB | Female GLB |
|---|---|---|
| Skin tone, hair colour, eye colour, shirt/pants/shoe colour | per-material colour override | palette swap of the GLB's own 32x32 6-colour texture (copy) |
| Height / width / thickness | root scale (1.0 = untouched) | same |
| Accessories (glasses, cap, backpack, scarf) + colour | optional boxes following head/torso bones (off by default) | same |
| Hairstyle, eye shape, eyebrows, expression, nose, mouth, face detail, shirt/pants/shoe style, arm length, leg length | **not supported** | **not supported** |

Unsupported options need different geometry, which would alter the supplied models. Their controls stay visible but are disabled
with a tooltip (`_lock` in `character_customization.gd`).

## Known limitations
* No jump exists in Phase 8 (no input action), so the GLB jump clips are unused and nothing was added.
* There is no crouch clip in either GLB: crouch uses the original procedural crouch retargeted to the skeleton.
* GLB clips are only used for walk/run; the game's walk speed (3.2 m/s) plays the Run clip, sprint plays it faster.
* Women's SitIdle has no sit-down motion (blended from idle); the Man's Sitting clip includes it.
* Chat/name-tag heights, camera and collision were not changed (the models are 1.83 m / 1.75 m tall, within the old capsule).

## Update: customization, seat and audio pass
- **Hair / face / accessories:** `scripts/player/avatar_kit.gd` draws hair styles, eyebrows, mouth, expression, nose, eye shape
  and face details on the head, fitted to measured head data (`AvatarKit.FACE`). Glasses and cap use the same numbers.
- **Clothing styles:** the shirt, pants and shoe surfaces are split into regions at load (`_regionize`) so styles can hide
  parts of them (tank top = no sleeves, shorts/capri = pants cut at the thigh/knee, sandals = no shoe upper). Longer
  trousers, long sleeves, bare arms/legs, boots and sandals are tubes glued to the limb bones (`_build_clothes`).
- **Arm / leg length:** limb bones are scaled each frame (`_apply_limb_scales`); hands and feet are counter-scaled and the
  model is lifted for longer legs.
- **Female mesh:** her single palette-textured surface is split into skin / hair / eyes / shirt / pants / shoes surfaces at load.
- **Sitting:** per-model `sit_gap` / `sit_dz`; legs follow the driven pose while seated so feet are flat at any seat height.
- **Footsteps:** per-foot adaptive plant detection; crouch steps come from the procedural gait phase.
