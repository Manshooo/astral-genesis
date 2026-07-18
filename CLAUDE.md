# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Astral Genesis** — a first-person post-apocalyptic roguelike dungeon-crawler in **Godot 4.7** (Forward+). The player is a disembodied consciousness ("БФЖ"/"Бифиж") escaped from a lab; the core mechanic is **body-snatching** enemies to survive (see ADR-0002). The project, docs, and code comments are written in **Russian** — match that language when adding comments and docs.

Engine specifics from `project.godot`: **Jolt Physics** (3D), Windows renderer forced to **d3d12**, physics runs on a separate thread, main scene is `src/world/world.tscn`.

## Running & building

- **Run/debug**: open the project in the Godot 4.7 editor and play the main scene, or use the Zed launch configs in `.zed/debug.json` (adapter `godot`). There is no CLI test suite.
- **Generator sanity check**: run `dev/gen_verifier.tscn` (F6) — it prints, across 20 seeds, room-preset library validation, "door undercapacity" (nodes with fewer doors than graph edges), and reachability from entry both by graph and by doors. Run this after touching world generation, `RS_RoomPresetLibrary`, or door/slot wiring.
- **Custom engine build**: `Dev.gdbuild` is a Godot build-profile that strips unused classes/modules (no 2D physics, no XR, no animation, etc.) for a lean export. Note it disables many classes — don't rely on 2D nodes, `Area3D`, `RayCast2D`, animation nodes, etc. in shipping code.
- **Assets** (`.glb`, `.svg`, images, etc.) are tracked via **Git LFS** (see `.gitattributes`). Text files are normalized to LF; source uses **hard tabs** (`.zed/settings.json`, `.editorconfig`).

## GECS (Entity-Component-System)

The entire game is built on **GECS** (`addons/gecs/`), a git **submodule** pinned to `release-v8.0.0` — do not edit files under `addons/gecs/` directly; they are upstream. Run `git submodule update --init` after cloning.

Core model:
- **Components** (`Component`, `src/components/`) are pure data — no logic. Class names `C_*`, files `c_*.gd`.
- **Systems** (`System`, `src/systems/`) hold all behavior. A system declares a `query()` (a `QueryBuilder`, e.g. `q.with_all([C_PlayerInput, C_BodySnatch]).with_none([C_UIBlocked])`) and a `process(entities, components, delta)`. Class names `S_*`, files `s_*.gd`. **System order matters** — declare cross-system ordering via `deps()` (`Runs.After`/`Runs.Before`).
- **Entities** (`Entity`, `src/entities/`) are containers, marked `@tool`. Class names `E_*`, files `e_*.gd`. Components attach either in the scene (`component_resources` in the inspector) or in code via `define_components()`. Identity components that must outlive the current body (e.g. `C_BodySnatch`, `C_Lifespan` on the player-soul) live in `define_components()`, not the scene — see `src/entities/player/e_player.gd`.
- **Observers** (`Observer`, `src/observers/`) react to component add/remove/change on any entity (`watch()` returns the component type). Class names `O_*`, files `o_*.gd`.
- Access the world via the `ECS` autoload: `ECS.world.query...`, `ECS.world.add_entity(e)`, `ECS.world.emit_event(&"name", entity)`.

**Frame loop** is driven manually in `src/world/main.gd`, which calls `ECS.process(delta, group)` for named groups in a fixed order:
- `_process` → `"input"` then `"gameplay"`
- `_physics_process` → `"physics"`

Systems are placed under `World/Systems/<group>` (a `SystemGroup` node) in `world.tscn`; the node name is the group. **Physics-raycasting systems (interaction detection, body-snatch) belong in the `"physics"` group** because Jolt runs on a separate thread and space-state queries are only safe from `_physics_process`.

New-script templates live in `src/script_templates/` (Godot picks these up when creating scripts) — use them so new components/systems/entities/observers follow the base-class conventions above.

### Знание: state machine в ECS — осторожно ([источник](https://ajmmertens.medium.com/why-storing-state-machines-in-ecs-is-a-bad-idea-742de7a18e59))

Наивный подход «один тег-компонент на каждое состояние» (`C_Idle`, `C_Walking`, `C_Attacking`, …) — плохая идея:
- **Взаимоисключение вручную**: состояния должны быть взаимоисключающими, но ECS этого не гарантирует — приходится вручную снимать старый тег и ставить новый, легко получить сущность в двух состояниях сразу.
- **Дорогие переходы**: частые add/remove тегов при переходах перекладывают/пересобирают данные сущности (в GECS смена набора компонентов бьёт по кэшу запросов), а переход состояния — операция «каждый кадр».
- **Разреженность и память**: много состояний × много сущностей → куча почти пустых тегов, плохая локальность.
- **God-система или диспетчинг**: логика скатывается либо в одну огромную систему на все состояния, либо в разрастающийся условный диспетчер.

**Как лучше в GECS**: держать состояние как *данные* — один компонент вроде `C_State { current: int/enum }` — и ветвить по нему внутри системы, а не кодировать состояние присутствием/отсутствием компонента. Отдельные компоненты навешивать только там, где состояние реально меняет *набор данных или запрос* (напр. `C_BodySnatch`/`C_Highlighted`), а не как чистый флаг-состояние.

### Знание: полезные GECS-паттерны из example_card_game «WAR» ([источник](https://github.com/csprance/gecs/tree/main/example_card_game))

Референс-реализация из репо GECS. Все API ниже сверены с нашим пиннутым `release-v8.0.0` и в аддоне присутствуют. Хорошая живая иллюстрация «FSM как данные» (см. заметку выше). Паттерны, которые стоит переиспользовать у нас:

- **Enum-FSM на синглтон-сущности** — `C_Phase { state: enum }`, сеттер эмитит `property_changed` вручную (прямое присваивание поля его не шлёт). Одна сущность матча/рана несёт текущую фазу. → применимо к флоу рана в `RunManager` (dealing/idle/travel/…), к флоу захвата тела и к death-флоу.
- **Дробление системы по состоянию через `sub_systems()` + property-query** — вместо одной god-системы с `match state`: `sub_systems()` возвращает пары `[query, callable]`, где запрос фильтрует по значению enum: `q.with_all([C_Match, {C_Phase: {"state": {"_eq": C_Phase.State.RESOLVE}}}])`. Каждое состояние = свой обработчик, движок сам маршрутизирует.
- **Отложенная смена состояния через CommandBuffer** — `cmd.add_custom(func(): c_phase.state = C_Phase.State.WAR)`. Флип фазы происходит после flush буфера, а не в середине итерации по сущностям (иначе меняешь то, по чему прямо сейчас идёт запрос). Структурные изменения (add/remove компонентов) — тоже через `cmd`.
- **Общий `SystemTimer` для многотактных секвенций** — создаётся один раз в `setup()`, хранится на компоненте (`C_Match.step_timer`), другие системы подхватывают его через `tick_source = c_match.step_timer`. `single_shot = true` + переармирование → пошаговое проигрывание секвенции (раздача, беаты анимации). → применимо к анимации захвата тела и переходам через двери.
- **Компоненты-запросы к презентации** — логика навешивает `C_Shake`/`C_Flash`/`C_PlayAudio`/`C_Pop`/`C_Burst`, отдельная визуальная/аудио-система исполняет эффект и снимает компонент. Развязывает геймплей и представление. У нас уже так устроено `C_Highlighted` → `O_OutlineVisual`; стоит держать этот стиль для новых эффектов.
- **Тег-компонент как time-boxed окно ввода** — `C_SlapWindow` существует только во время короткого окна; система ввода фильтрует по его наличию, по истечении окна логика его снимает. → применимо к тайминговым окнам взаимодействия/захвата.
- **Отношения с данными** — `C_AtSpot { order }` = позиция карты в стопке: упорядоченное членство моделируется relationship c payload, а не массивом-списком. → применимо к содержимому комнат/инвентарю.
- **Развязка логика→UI через кастомные события** — `_world.emit_event(&"round_resolved", match_e, {...})`; UI-наблюдатели слушают и рендерят, системы логики про UI ничего не знают.

## Source layout & naming

`src/` folders are colored in the editor (`project.godot [file_customization]`) and files are prefixed by role:

| Prefix | Class | Folder | Role |
|---|---|---|---|
| `c_` | `C_*` | `components/` | data components |
| `s_` | `S_*` | `systems/` | behavior systems |
| `e_` | `E_*` | `entities/` | entity scenes/scripts |
| `o_` | `O_*` | `observers/` | component observers |
| `a_` | `A_*` | `resources/interaction/`, entity dirs | interaction actions (`RS_InteractionAction`) |
| `rs_` | `RS_*` | `resources/` | data resources (configs, graph, presets, skills) |

Autoloads (`project.godot [autoload]`, scripts in `src/autoloads/`): `ECS`, `GameConfig` (loads `data/game_config.tres` → `RS_GameConfig`), `SettingsManager`, `SkillManager`, `UIManager`, `WorldSave`, `RunManager`. Tunable game data lives as `.tres` resources under `data/` (skill tree, room presets, game config, settings), edited in-editor rather than hardcoded.

## World generation & run flow

A "run" is a **graph**, not a linear level. Key pieces:

- **`RS_LevelGraph.generate_run(seed, library)`** (`src/resources/world_generator/rs_level_graph.gd`) deterministically builds the whole complex: layers by depth `[4,3,2,1,0]` (surface = 0), each layer = 1–3 floors of ~4 rooms connected by a spanning tree + extra edges, layers joined by vertical hub connectors (some `locked_by` a key). The player's home lab is a guaranteed **dead-end** at `HOME_DEPTH = 3`; exits (`level_exit` tag) are placed on the surface layer. Room scenes are assigned last via `RS_RoomPresetLibrary.select_preset(node, rng)`; the entry node is always overridden to the hand-authored **hub** scene.
- **`RunManager`** (autoload) owns one active run: it spawns/despawns the single current room and teleports the player. It does **not** stream neighbors yet. Seed comes from `WorldSave.save.run_seed()` (derived from `world_seed` + `death_count`), so generation is reproducible.
- **`WorldSave`** persists `RS_WorldSave` (`world_seed` + `death_count`) to `user://world_save.tres`. New Game rolls a new seed; death increments `death_count` (changing future generation) — the death flow itself is not wired yet.

### Doors ↔ graph edges (ADR-0001) — read before touching room/door code

Graph edges (`RS_LevelConnection`) and physical room doors are bridged at spawn time, **not** authored by hand:
- Each door is an interactable Entity carrying **`C_DoorSlot { slot_id }`** (stable per-prefab id).
- On spawn, `RunManager._bind_doors` picks the room's `C_DoorSlot` entities (a subset of the already-registered nested entities), sorts them deterministically by `slot_id`, and **stamps `C_DoorPortal { target_node_id, locked_by }`** onto each from the node's `connections`. Surplus slots (more doors than edges) are **sealed** (`C_Interactable.enabled = false`). More edges than doors → warning, some nodes unreachable (that's what `gen_verifier` measures).
- Traversal goes through the interaction system: `A_TravelThroughDoor` reads its entity's `C_DoorPortal`, checks the lock, and calls `RunManager.travel_to(target_node_id)`. On arrival the player is placed at the door leading back to where they came from (fallback: the room's `SpawnPoint`).
- **Caveat**: `world.add_entity(room)` registers ONLY the room itself — GECS does not walk the tree for nested `Entity` children. `RunManager` registers **all** nested entities (`Incubator`, doors, …) explicitly via `_register_room_children` and removes them in `_despawn_current_room` (`_current_room_children`, with `_current_room_doors` as the door subset). Keep that invariant when changing room spawn/despawn. Removal filters `is_instance_valid` first: `RunManager` is an autoload, so after an exit-to-menu the previous run's entity refs are dangling (freed with the old world), and `remove_entity`'s typed param rejects freed objects before its own guard runs.

Current slot↔edge matching is by sorted order (bootstrap "Variant A"); the ADR's target is presets declaring their slots with `slots >= connections`. See `docs/astral-genesis/adr/`.

## Interaction system (see docs/astral-genesis/how-to/Взаимодействие.md)

An interactable object needs three things: a **`C_Interactable`** component, a collider on the **`interactives` physics layer (layer_4, mask bit 8)**, and either an `interact()` method or `actions[]` of `RS_InteractionAction`. `S_InteractionDetector` raycasts from the player camera each physics frame and walks *up* the node tree from the hit collider to find the owning `Entity` (so the collider may live deep inside an imported scene, not on the Entity itself). It toggles `C_Highlighted`, which drives crosshair growth and the outline observer (`O_OutlineVisual`). Outline only finds meshes that are a `GeometryInstance3D` root or a child named exactly `MeshInstance3D`.

## Conventions & docs

- Architecture decisions are recorded as ADRs in `docs/astral-genesis/adr/` (Russian). Read the relevant ADR before reworking doors/graph (0001), body-snatch/embodiment (0002), or room presets (0003). The `docs/astral-genesis/` tree is an Obsidian vault.
- Physics layers: 1 `colliders`, 2 `player`, 3 `enemies`, 4 `interactives`. Systems reference these by bit (e.g. body-snatch raycasts only `enemies` = `1 << 2`).
