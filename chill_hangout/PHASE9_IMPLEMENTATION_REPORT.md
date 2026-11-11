# Chill Hangout — Phase 9 Character Model Integration Report

**Prepared:** 11 November 2026  
**Source project:** `chill_hangout_phase8.zip`  
**Scope:** Replace the Phase 8 procedural male/female avatar visuals with the two supplied Quaternius GLB assets. No unrelated game systems were intentionally changed.

## 1. Delivered files

| File | Change |
|---|---|
| `assets/characters/male_character.glb` | Added the supplied male GLB, copied without modification. |
| `assets/characters/female_character.glb` | Added the supplied female GLB, copied without modification. |
| `scripts/player/character_model.gd` | Updated `CharacterModel` to instantiate the correct GLB, resolve its animation player and skeleton, map the two rigs independently, retain the existing emote choreography through bone-pose proxies, and support compatible male material color overrides. |
| `scripts/player/player.gd` | Passed the local player's airborne state to `CharacterModel.animate()` so the imported jump clip can be selected. Existing callers remain compatible because the new parameter is optional. |

All other original Phase 8 files were left unchanged. `PHASE9_IMPLEMENTATION_REPORT.md` is this delivery note.

## 2. Model and asset preservation

The GLB files were copied byte-for-byte from the uploaded originals. Their SHA-256 hashes are:

- Male: `dad8fa3ca2bc7760892f9ff47f544941179e50acb2aa772cf9f035154a37fc58`
- Female: `97a4e8c5e93b5c4f68b25e5240f308aa81ff4ae487b750e62f13e02c338d73e8`

The male GLB contains one skinned mesh, six named materials (`Shirt`, `Skin`, `Pants`, `Eyes`, `Socks`, `Hair`) and eleven animation clips. The female GLB contains one skinned mesh, one textured material and ten animation clips. Original GLB geometry and imported materials are not rewritten by this integration.

The wrapper applies a uniform visual fit scale based on the source mesh bounds and the existing 1.8-unit player capsule: `0.372` for the male and `0.34` for the female. These are source-file-bound estimates and still require in-engine visual confirmation. The supplied GLBs are also rotated at their scene root to retain the Phase 8 `-Z` forward-facing character convention. Neither change edits the underlying GLB files.

## 3. Animation and emote integration

Animation lookup is model-specific because the supplied skeletons and animation names differ.

| Gameplay state | Male clip | Female clip |
|---|---|---|
| Idle | `Man_Idle` | `Idle` |
| Walk | `Man_Walk` | `Walking` |
| Run | `Man_Run` | `Running` |
| Jump | `Man_Jump` (or `Man_RunningJump` while moving quickly) | `Jump` |
| Sit | `Man_Sitting` | `Sitting`, then `SitIdle` |
| Stand after sitting | `Man_Standing` | Falls back to normal locomotion transition |

Imported clips are duplicated into a per-instance runtime animation library to set looping or one-shot playback without mutating the imported source animations.

The five existing Phase 8 emote IDs and choreography remain in `CharacterModel`: Brazilian TikTok Dance, Sipping a Coffee, Stranger Things Dance, Hi, and Aura Farm. Their procedural pose controls are mapped to the major bones of each separate rig. The visual model itself is the supplied GLB; the pose proxy contains no replacement body meshes. The existing main-menu greeting also continues to drive the right-arm proxy, which is mapped to the matching GLB upper-arm bone. This is a retargeting approximation based on the inspected bone names and has **not** been visually validated in Godot. The existing coffee mug and “HI” emote props remain as before.

The local player now supplies its airborne state. The existing multiplayer snapshot does not include an airborne flag, so no protocol or server changes were made; remote-player jump selection remains limited by the Phase 8 state data.

## 4. Customization compatibility

The customization screens, controls, appearance data schema, apply/reset/save flow and `user://character.json` handling were not changed. Gender selection continues to choose the corresponding model through the existing appearance dictionary.

To protect each supplied model's default appearance:

- No material override is applied when the saved option equals that model's default appearance values.
- The male model's separately named material slots allow non-destructive runtime color overrides for shirt, skin, pants, eyes, socks/shoes, and hair. Runtime overrides duplicate the material rather than altering the imported source material.
- The female model has a single textured material. Part-specific recoloring is not applied because it would affect the combined material/texture rather than one intended region.
- Body proportions, hair styles, face geometry/details, clothing cuts, and accessories are not procedurally rebuilt on either GLB. Their original UI/data fields remain in the existing customization system, but these options do not change the supplied model geometry. This is an intentional fidelity limitation, not a claim that those controls have been fully adapted.

## 5. Existing systems preserved

No changes were made to the customization UI script, appearance-data schema, profile save/load implementation, networking protocol, game server, room state, lobby scenes, name-tag script, emote menu, or unrelated assets. The existing appearance dictionary (including gender) remains the client/server contract; model geometry is loaded locally from the packaged GLB assets rather than sent over the network.

## 6. Testing report

The execution environment used to prepare this ZIP did not contain a Godot executable or editor. Therefore the project could not be imported, launched, or exercised in the engine. Static checks are not presented as runtime proof.

| Check | Status | Evidence / notes |
|---|---|---|
| Original Phase 8 ZIP integrity | **PASS** | Archive integrity check completed without a corrupt entry. |
| Male GLB copy integrity | **PASS** | Integrated copy is byte-for-byte identical to uploaded source; GLB v2 header and declared file length validated. |
| Female GLB copy integrity | **PASS** | Integrated copy is byte-for-byte identical to uploaded source; GLB v2 header and declared file length validated. |
| Required GLB preload paths | **PASS** | Both referenced files exist at their project paths. |
| Existing `CharacterModel` public method names | **PASS — static inspection only** | `preset`, `create`, `rebuild`, `animate`, `play_emote`, `stop_emote`, `get_emote`, `get_right_hand_position`, and `get_right_shoulder` remain present. |
| Existing emote identifiers | **PASS — static inspection only** | All five original `NetProtocol` emote identifiers remain referenced in `CharacterModel`; the networking and UI source files are unchanged. |
| Unrelated Phase 8 files | **PASS — file comparison** | Compared against the original ZIP: no original files are missing; only the two listed scripts differ, and the two GLBs are the only added assets (excluding this report). |
| Godot project import / GDScript parse | **NOT TESTED** | Godot 4.3+ is not installed in the execution environment. |
| Character appearance and forward orientation in-game | **NOT TESTED** | Requires rendering in Godot. |
| Model scale, floor contact, camera framing and name-tag placement | **NOT TESTED** | Fit values are estimated from source GLB bounds only. |
| Idle / walk / run / jump / sit / stand playback | **NOT TESTED** | Imported clips and rig names were inspected in the GLB data; actual Godot playback was unavailable. |
| Five emotes on both rigs | **NOT TESTED** | Bone-map implementation is present, but pose quality and transitions need in-engine validation. |
| Customization preview, controls, reset, save and load | **NOT TESTED** | Scripts and data flow were statically inspected; no UI session was run. |
| Local gameplay movement and collision | **NOT TESTED** | Requires Godot runtime. |
| Multiplayer appearance, movement and emote synchronization | **NOT TESTED** | No server/client runtime session was available. |
| Regression / full Phase 8 feature suite | **NOT TESTED** | Requires Godot runtime and a multiplayer test session. |
| Requested comparison screenshots | **NOT TESTED / NOT GENERATED** | No Godot renderer was available. No fabricated “integrated” screenshots are included. |

## 7. Required verification before treating the integration as complete

Open the ZIP's `chill_hangout/project.godot` in Godot 4.3 or a compatible Godot 4.x release, allow both GLBs to import, then inspect the male/female previews and run the existing character, emote, save/load and multiplayer tests. In particular, verify the root facing direction, 1.8-unit visual fit, seat alignment, each imported animation's bone tracks, and the proxy-to-bone emote poses. Capture the six requested source/in-game screenshots after those checks. Any corrections should remain limited to `character_model.gd` and, only if required, `player.gd`.

**Delivery status:** The source-level integration and ZIP packaging are prepared. This is not an engine-tested or fully verified game build because the required Godot runtime checks and screenshots could not be performed here.
