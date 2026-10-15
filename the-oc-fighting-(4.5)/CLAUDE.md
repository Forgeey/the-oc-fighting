# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**The OC Fighting** is a 2D fighting game prototype built in Godot 4.2+ (currently targeting 4.5). It is a local multiplayer fighter featuring two playable characters with melee combat, directional inputs, special moves (motion inputs), jumping, dodging, and hitbox-based collision. The project is currently in active development with placeholder art and early-stage mechanics.

## Important: Fray Addon Architecture

The entire game logic is built on top of the **Fray** addon (`addons/fray/`), a modular Godot 4 framework for action/fighting games. Fray provides three core subsystems that the game uses extensively. Do NOT reimplement these; extend them.

### 1. Fray State Machine (`addons/fray/src/state_mgmt/`)
- **`FrayStateMachine`** (Node): Drives state transitions. Attached to each player's CharacterBody2D.
- **`FrayCompoundState`** (Resource): Container for states and transitions. Built via `FrayCompoundState.builder()`.
- **`FrayState`** (Resource): Base class for all game states. Each state script in `script/state_script/` extends this.
  - Key virtual methods: `_ready_impl(context)`, `_enter_impl(args)`, `_exit_impl()`, `_physics_process_impl(delta)`, `_process_impl(delta)`
  - Context dictionary is passed from `character_body_2d.gd` via `state_machine.initialize(context, root)`
- **Builder pattern** is used to construct the entire state graph in `_ready()`:
  - `.add_state(name, state_obj)`
  - `.transition_press(from, to, {input: "name"})`
  - `.transition_sequence(from, to, {sequence: "name"})`
  - `.transition(from, to, {prereqs: [...]})`
  - `.tag_multi(states, tags)` + `.add_rule(from_tag, to_tag)` for global transitions
  - `.register_conditions({name: callable})`
- **Advance mode**: The state machine is set to `advance_mode = MANUAL` (value 2) and advanced manually each frame via `state_machine.advance()` in `_physics_process`.

### 2. Fray Input System (`addons/fray/src/input/`)
- **`FrayInput`** (autoload singleton): Reads bound inputs and composite inputs every physics frame. Emits `input_detected`.
- **`FrayInputMap`** (autoload singleton): Registers input binds and composite inputs.
  - `add_bind_action(name, godot_action)` — maps a Fray input name to a Godot InputMap action.
  - `add_composite_input(name, composite)` — registers combination/conditional/group inputs.
- **Composite inputs** for directional logic (relative to opponent position):
  - `FrayConditionalInput`: Chooses between components based on a condition Callable. Used for forward/backward (depend on which side of the opponent the player is on).
  - `FrayCombinationInput`: Multi-button inputs (e.g., forward+jump) with SYNC/ASYNC/ORDERED modes.
- **`FrayBufferedInputAdvancer`**: Child of `FrayStateMachine`. Receives buffered input presses/sequences and feeds them to `state_machine.advance()`.
  - `buffer_press("input_name")`, `buffer_sequence("sequence_name")`
  - `paused` property can temporarily stop input consumption.
- **`FrayInputBuffer`** (Node): Provides jump buffering and coyote time. `is_pressed_or_buffered("input")` is used for jump input.
- **`FraySequenceMatcher`**: Detects motion/command inputs. Initialized with a `FraySequenceTree` containing `FraySequenceBranch` objects.
  - In `arena.gd`, matcher matches the "shuweiban" sequence (forward → backward → attack).

### 3. Fray Hitbox System (`addons/fray/src/hit/`)
- **`FrayHitStateManager2D`**: Node under `VisualRoot`. Only one child `FrayHitState2D` can be active at a time.
- **`FrayHitState2D`**: Container for hitboxes representing a combat state (idle, jump, attack, etc.).
  - `active_hitboxes` is a bitflag controlling which child `FrayHitbox2D`s are active.
  - Activated/deactivated via AnimationPlayer method tracks calling `set_hitbox_active(index, true/false)`.
- **`FrayHitbox2D`**: Extends `Area2D`. Has an `attribute` (extends `FrayHitboxAttribute`).
- **`FrayHitboxAttribute`**: Abstract resource. Override `_get_color_impl()` and `_allows_detection_of_impl()`.
- Custom attributes:
  - `AttackAttribute` (`script/hit_state_script/AttackboxAttribute.gd`): Red, allows detection of others.
  - `HurtboxAttribute` (`script/hit_state_script/HurtboxAttribute.gd`): Blue, blocks detection of other hurtboxes.
- **Collision flow**: Hitbox enters → `hitbox_entered` → `hitbox_intersected` signal bubbles up → `FrayHitStateManager2D.hitbox_intersected` → `_hitbox_detect()` in `character_body_2d.gd`.

## Player Actor Structure

Each player is instantiate from `core/component/player.tscn`:

```
Player (Node2D)
└── CharacterBody2D (script/component/character_body_2d.gd)
    ├── Label
    ├── PushBox (Area2D — core/component/push_box.gd)
    ├── AnimationPlayer
    ├── FrayAnimationObserver (with AnimatorTrackerAnimationPlayer)
    ├── FrayStateMachine
    │   └── FrayBufferedInputAdvancer
    ├── VisualRoot (Node2D — flipped via scale.x for facing)
    │   ├── Sprite2D
    │   └── FrayHitStateManager2D
    │       ├── Idle_HitState2D (Head/Body Hurtboxes)
    │       ├── Jump_HitState2D (Head/Body Hurtboxes)
    │       └── 1_HitState2D (Head/Body Hurtboxes + Attack_Hitbox2D)
    └── FrayInputBuffer
```

Key points:
- **Facing/VisualRoot**: `VisualRoot.scale.x` is flipped (-1 or 1) to make the sprite face the opponent. All hitboxes are children of VisualRoot, so they flip together.
- **is_facing_right**: Boolean flag on `CharacterBody2D` set by `arena.gd` based on relative position.
- **AnimationObserver**: Listens to AnimationPlayer events. `usignal_finished("animation_name")` returns a Signal that fires when that animation ends. Used to return to idle after attacks/hurt.

## Game State Scripts (`script/state_script/`)

All extend `FrayState`. They receive the `context` dictionary in `_ready_impl` containing: `actor`, `sprite`, `anim_observer`, `anim_player`, `state_machine`.

| State | Key Behavior |
|-------|-------------|
| `idle_script.gd` | Plays "idle" animation, zeroes horizontal velocity. |
| `forward_script.gd` / `backward_script.gd` | Moves at constant speed, direction depends on `actor.is_facing_right`. |
| `jump_script.gd` | Applies upward velocity, transitions to `float_state` when `velocity.y >= 0`. |
| `double_jump_script.gd` | Decrements `remaining_air_jumps`, similar to jump. |
| `float_script.gd` | Applies gravity, `move_and_slide()`. |
| `land_script.gd` | Resets `remaining_air_jumps`, returns to idle when animation finishes (`_is_done_processing_impl`). |
| `dodge_script.gd` | Plays "dodge" animation (class name is `ParryState` despite file name). |
| `attack_script.gd` | Plays "中击_attack_1", connects to `usignal_finished` to return to idle. |
| `attack2_script.gd` | Plays "中击_attack_2", includes a manual position adjustment on finish (40px forward). |
| `hurt_script.gd` | Plays "hurt", returns to idle on animation finish. |

## Scene Management

`script/screen/scene_manager.gd` is an autoload singleton with a `SCENES` dictionary mapping names to `.tscn` paths. Use `SceneManager.change_scene("arena")` to switch.

## Arena Scene (`core/screen/arena.tscn`)

- Instantiates two `Player`s at positions (300, 550) and (800, 550).
- Handles input mapping initialization (`_init_player_control`):
  - P1: WASD + J/K (attack/attack2)
  - P2: Arrow keys
  - Forward/backward are conditional composites that depend on relative position.
- Reads raw Godot input in `_physics_process` and buffers presses via `advancer.buffer_press("input_name")`.
- Initializes sequence matcher for special moves.
- Camera script (`script/component/camera_2d.gd`) tracks midpoint between players and zooms out when they separate.
- Pushbox collision (`Pushbox` class) prevents character overlap by adjusting positions when pushboxes intersect.

## Godot Version and Rendering

- **Godot 4.5** (as declared in `project.godot` features array)
- **Rendering**: Forward Plus
- **Pixel snap enabled**: `snap_2d_transforms_to_pixel=true`, `snap_2d_vertices_to_pixel=true`
- **Texture filter**: Nearest (`default_texture_filter=0`) for pixel art

## Running the Project

This is a standard Godot project. Open the project root in Godot Editor and run the main scene.

```bash
# If Godot is in PATH and this is run from the repo root:
godot --path .
# Or to run a specific scene:
godot --path . --scene core/screen/arena.tscn
```

There is no custom build system, test runner, or linter configured. GDScript files are validated by the Godot editor's built-in parser.

## Export

An export preset for "Windows Desktop" exists in `export_presets.cfg`. Export via the Godot editor or CLI:

```bash
godot --export-release "Windows Desktop" ./build/game.exe
```

## File Naming Conventions

- Scripts: `snake_case.gd`
- Classes: `PascalCase` with explicit `class_name`
- Scene files: `snake_case.tscn`
- Animator animation names: Mix of English and Chinese (e.g., "中击_attack_1", "1_attack")
- State script files: `{state_name}_script.gd` with corresponding `class_name {PascalCase}State`

## Notes for AI Assistants

- **Do not use `is_instance_valid()` unless necessary.** The project uses it in `LandState._is_done_processing_impl`.
- **Facing direction is critical.** Any new animation-based state must account for `is_facing_right`. VisualRoot.scale.x handles sprite/hitbox flipping.
- **Always use Fray's builder pattern** for state machine modifications in `character_body_2d.gd`. Do not manually construct `FrayCompoundState`.
- **Hitbox activation is animation-driven.** Use AnimationPlayer method tracks targeting `FrayHitState2D.set_hitbox_active(index, bool)`.
- **Input handling is split**: Godot InputMap → FrayInputMap → FrayInput → (Arena buffers) → BufferedInputAdvancer → StateMachine.advance(). When adding new inputs, register them in arena.gd's `_init_player_control`.
- **The Fray addon is a third-party dependency.** It is MIT licensed (by Pyxus) and currently in alpha. Avoid deep modifications to `addons/fray/` unless necessary; prefer extending via game-side scripts.
