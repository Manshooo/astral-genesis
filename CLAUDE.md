# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Astral Genesis** — a first-person post-apocalyptic roguelike dungeon-crawler in **Godot 4.7** (Forward+). The player is a disembodied consciousness ("БФЖ"/"Бифиж") escaped from a lab; the core mechanic is **body-snatching** enemies to survive. The project, docs, and code comments are written in **Russian** — match that language when adding comments and docs.

Engine specifics from `project.godot`: **Jolt Physics** (3D), Windows renderer forced to **d3d12**, physics runs on a separate thread. The **boot scene** is `src/levels/menu_map/L_menu_map.tscn` (the main menu with an animated 3D background); **New Game** loads the gameplay scene `src/world/world.tscn`.

## Running & building

- **Run/debug**: open the project in the Godot 4.7 editor and play the project (boots to the main menu → **New Game** enters `world.tscn`), or play `world.tscn` directly to skip straight into a run. Zed launch configs live in `.zed/debug.json` (adapter `godot`). There is no CLI test suite.
- **Generator sanity check**: run `dev/gen_verifier.tscn` (F6) — it prints, across 20 seeds, room-preset library validation, "door undercapacity" (nodes with fewer doors than graph edges), and reachability from entry both by graph and by doors. Run this after touching world generation, `RS_RoomPresetLibrary`, or door/slot wiring. The **Генератор** dock (`addons/level_gen_tool`) does the same validation plus a per-seed selection breakdown interactively; prefer it over `dev/preset_stats.gd`, which runs via `godot --script` where autoloads don't exist, so `Entity` fails to compile and every check silently degrades.
- **Assets** (`.glb`, `.svg`, images, etc.) are tracked via **Git LFS** (see `.gitattributes`). Text files are normalized to LF; source uses **hard tabs** (`.zed/settings.json`, `.editorconfig`).

## GECS (Entity-Component-System)

The entire game is built on **GECS** (`addons/gecs/`), a git **submodule** pinned to `release-v9.2.0` — do not edit files under `addons/gecs/` directly; they are upstream. Run `git submodule update --init` after cloning.

Core model:
- **Components** (`Component`, `src/components/`) are pure data — no logic. Class names `C_*`, files `c_*.gd`.
- **Systems** (`System`, `src/systems/`) hold all behavior. A system declares a `query()` (a `QueryBuilder`, e.g. `q.with_all([C_PlayerInput, C_BodySnatch]).with_none([C_UIBlocked])`) and a `process(entities, components, delta)`. Class names `S_*`, files `s_*.gd`. **System order matters** — declare cross-system ordering via `deps()` (`Runs.After`/`Runs.Before`).
- **Entities** (`Entity`, `src/entities/`) are containers, marked `@tool`. Class names `E_*`, files `e_*.gd`. Components attach either in the scene (`component_resources` in the inspector) or in code via `define_components()`. Identity components that must outlive the current body (e.g. `C_BodySnatch`, `C_Lifespan` on the player-soul) live in `define_components()`, not the scene — see `src/entities/player/e_player.gd`.
- **Observers** (`Observer`, `src/observers/`) react to component add/remove/change on any entity (`watch()` returns the component type). Class names `O_*`, files `o_*.gd`.
- Access the world via the `ECS` autoload: `ECS.world.query...`, `ECS.world.add_entity(e)`, `ECS.world.emit_event(&"name", entity)`.

**Frame loop** is driven manually in `src/world/main.gd`, which calls `ECS.process(delta, group)` for named groups in a fixed order:
- `_process` → `"input"` then `"gameplay"`
- `_physics_process` → `"physics"`

Systems are placed under `World/Systems/<group>` in `world.tscn`; each `<group>` is a plain `Node` whose **name** is the group (`input`/`gameplay`/`physics`), and the `World` node points GECS at them via `system_nodes_root = NodePath("Systems")`. **Physics-raycasting systems (interaction detection, body-snatch) belong in the `"physics"` group** because Jolt runs on a separate thread and space-state queries are only safe from `_physics_process`.

**Editor docks** (`addons/entity_template_tool` → «Шаблоны», `addons/level_gen_tool` → «Генератор», same dock slot = two tabs). Two traps, both already paid for:
- Any resource a dock calls into must be `@tool` — otherwise the editor loads it as a **placeholder** and every method call dies with "Attempt to call a method on a placeholder instance". That is why `RS_LevelGraph`, `RS_LevelNode`, `RS_LevelConnection`, `RS_LevelLayer`, `RS_RoomPreset`, `RS_RoomPresetLibrary` and `RS_RoomLayout` carry `@tool` despite being pure data. Property reads still work on a placeholder, so the failure only shows up on the buttons.
- A dock's *minimum* size is demanded by the editor for **every** tab at startup, before any of them is opened. A `Label` with `autowrap_mode != OFF` computes its minimum height by wrapping at its minimum **width** (~17 px pre-layout), so a one-line status label reported 1277 px and stretched the whole right panel until the tab was first clicked. Status lines use `AUTOWRAP_OFF` + `OVERRUN_TRIM_ELLIPSIS` with the full text in the tooltip; keep `custom_minimum_size` heights small and let `SIZE_EXPAND_FILL` do the work.

New-script templates live in `src/script_templates/` (Godot picks these up when creating scripts) — use them so new components/systems/entities/observers follow the base-class conventions above.

### Правило v9: структурные изменения — только через `cmd` (командный буфер)

С GECS v9 `System.safe_iteration` по умолчанию **`false`**: система обходит массивы архетипов **zero-copy**, без защитной копии (в v8 копия делалась каждый кадр). Отсюда главный инвариант:

**Внутри `process()` нельзя менять СТРУКТУРУ мира напрямую** — `entity.add_component/remove_component`, `ECS.world.add_entity/remove_entity`, отношения. Такое изменение переносит сущность между архетипами через swap-remove и **пропускает** соседние сущности в текущем цикле; при `gecs/settings/debug_mode=true` (у нас включён) GECS дополнительно роняет `push_error` «structural change during zero-copy system iteration». Менять **поля** компонентов (`health.current -= x`) можно свободно — это не структурное изменение.

Три способа, все применяются в проекте:
- **`cmd.*` — по умолчанию.** `cmd.add_component/remove_component/add_entity/remove_entity` копятся и применяются сразу после `process()` этой системы (`FlushMode.PER_SYSTEM`), причём remove+add коалесцируются в ОДИН переезд архетипа. Примеры: `S_Health`, `S_Lifespan`, `S_InteractionDetector`, `S_BodySnatch`.
  - Событие, которое должно уйти ПОСЛЕ применения правок, тоже кладём в буфер: `cmd.add_custom(func(): ECS.world.emit_event(&"body_snatched", soul))` — иначе наблюдатель увидит старое состояние (см. `S_BodySnatch._embody`).
- **`call_deferred` — когда операция сносит комнату/меняет сцену.** Переход через дверь и конец забега трогают полмира, поэтому уходят за пределы прохода ECS целиком: `S_InteractInput` (`target.interact.call_deferred()`), `O_ExpelFromBody`, `O_RunEnded`. Наблюдатели, вызванные из `emit_event` внутри `process()`, находятся в том же окне итерации — на них правило распространяется.
- **`safe_iteration = true`** в `_init()` конкретной системы — аварийный откат к v8-поведению. Не использовать без причины; проектный ключ `gecs/settings/safe_iteration_default` не трогаем.

Прочее из v9, что стоит знать:
- **Идентичность сущности** — `entity.id` теперь `int`-хэндл (не String UUID), выдаётся при `add_entity`; `ecs_id` больше нет. Имя-синглтон задаётся отдельным полем `entity.alias: StringName` (`world.get_entity_by_alias`), проверка живости — `world.is_alive(id)`. В нашем коде идентичность нигде не используется — при добавлении не изобретать String-id.
- **Порядок `world.entities` нестабилен** (O(1) swap-remove при удалении) — не полагаться на порядок вставки, сортировать явно. Ср. `RunManager._bind_doors`, который специально сортирует двери по `slot_id`.
- **Пустые архетипы не удаляются** (переиспользуются при спавн/деспавн-чурне комнат). Освободить их можно `world.compact()` в спокойный момент — кандидат на вызов при смене узла/конце забега, если профайлер покажет рост.
- **`q.changed([C_X])`** — система получает только сущности, чей компонент писался с её прошлого прогона (детект по `property_changed`, после прямой мутации — `entity.mark_changed(component)`). Пока нигде не используем; полезно для дорогих реактивных систем.
- **`GECSTracker.track(callable)`** (появился в 9.2.0) — прогоняет вычисление и возвращает его фактические зависимости: выполненные запросы (`.queries`) и прочитанные типы компонентов (`.reads`), видит их сквозь вложенные вызовы. Плюс `QueryBuilder.sensitivity()` — пути скриптов, чья мутация влияет на членство в запросе. Заготовка под реактивные производные и инвалидацию кэша; выключен по умолчанию, не реентерабелен (`track()` нельзя вкладывать). См. `addons/gecs/docs/DEPENDENCY_TRACKING.md`.
- Обновление аддона: `git submodule update --remote addons/gecs` не годится — ветка пиннится в `.gitmodules` (`branch = release-v9.2.0`). Сменить версию = поправить `branch` и переключить сабмодуль на новую ветку. После смены версии переимпортировать проект; если менялся **путь** аддона — сначала **удалить `.godot/uid_cache.bin`**, иначе кэш UID помнит старые пути и ломает автолоад `ECS`.

### Знание: state machine в ECS — осторожно ([источник](https://ajmmertens.medium.com/why-storing-state-machines-in-ecs-is-a-bad-idea-742de7a18e59))

Наивный подход «один тег-компонент на каждое состояние» (`C_Idle`, `C_Walking`, `C_Attacking`, …) — плохая идея:
- **Взаимоисключение вручную**: состояния должны быть взаимоисключающими, но ECS этого не гарантирует — приходится вручную снимать старый тег и ставить новый, легко получить сущность в двух состояниях сразу.
- **Дорогие переходы**: частые add/remove тегов при переходах перекладывают/пересобирают данные сущности (в GECS смена набора компонентов бьёт по кэшу запросов), а переход состояния — операция «каждый кадр».
- **Разреженность и память**: много состояний × много сущностей → куча почти пустых тегов, плохая локальность.
- **God-система или диспетчинг**: логика скатывается либо в одну огромную систему на все состояния, либо в разрастающийся условный диспетчер.

**Как лучше в GECS**: держать состояние как *данные* — один компонент вроде `C_State { current: int/enum }` — и ветвить по нему внутри системы, а не кодировать состояние присутствием/отсутствием компонента. Отдельные компоненты навешивать только там, где состояние реально меняет *набор данных или запрос* (напр. `C_BodySnatch`/`C_Highlighted`), а не как чистый флаг-состояние.

### Знание: полезные GECS-паттерны из example_card_game «WAR» ([источник](https://github.com/csprance/gecs/tree/main/example_card_game))

Референс-реализация из репо GECS. Все API ниже сверены с нашим пиннутым `release-v9.2.0` и в аддоне присутствуют. Хорошая живая иллюстрация «FSM как данные» (см. заметку выше). Паттерны, которые стоит переиспользовать у нас:

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

**Key rebinding** lives in `SettingsManager`: `RS_Settings.keybinds` maps an action to a short code string (`"key:70"`, `"mouse:1"` — codec `event_to_code`/`code_to_event`) and holds **only deltas** from `project.godot`. Applying always starts from `InputMap.load_from_project_settings()` and layers the overrides on top, so an empty dict *is* "defaults" and Reset needs no stored copy. `SettingsManager.REBINDABLE_ACTIONS` is the ordered action→label list the UI renders (`src/ui/settings/keybinds_setting.gd`, one settings-control for the whole dict); `pause_game` is deliberately excluded because Esc is a UI-wide invariant. Codes are strings, not `InputEvent` resources, because resources compare by reference and the settings draft would always look dirty. When adding a `Dictionary` setting, remember `Resource.duplicate()` shares it — use `RS_Settings.copy()`.

## World generation & run flow

A "run" is a **graph**, not a linear level. Key pieces:

- **Entry point**: the game boots into the `L_menu_map.tscn` main menu. **New Game** (`src/ui/main_menu/main_menu.gd`) rolls a fresh seed via `WorldSave.new_game()` and loads `world.tscn`, whose root `main.gd` calls `RunManager.enter_complex()` in `_ready` — that is what actually starts a run.
- **`RS_LevelGraph.generate_run(seed, library)`** (`src/resources/world_generator/rs_level_graph.gd`) deterministically builds the whole complex: layers by depth `[4,3,2,1,0]` (surface = 0), each layer = 1–3 floors of ~4 rooms connected by a spanning tree + extra edges (floors within a layer joined by `floor_hub` connectors), layers joined by `vertical_hub` connectors (some `locked_by` the `level_access_key`). Room scenes are assigned last via `RS_RoomPresetLibrary.select_preset(node, rng)`; the entry node is always overridden to the hand-authored **hub** scene.
  - **Two guaranteed dead-ends**, both built by `_generate_floor(dead_end_index)` on room 0 / floor 0 of their layer and both excluded from the `vertical_hub` pool (a connector would give them a second edge): the home lab at `HOME_DEPTH = 3` (entry needs degree 1) and one surface room at `SURFACE_DEPTH = 0`. The surface one exists so `exit_room` — which serves only one graph edge — always has a node it fits; without it a run could be literally unwinnable, since a `level_exit` node dressed as a vertical hub has no `A_FinishRun` door. `_place_exits` orders candidates accordingly: non-`vertical_hub` nodes first, then by ascending degree. Measured over 60 seeds: 75% of exit nodes get a real exit room and 60/60 runs have at least one working exit.
- **`RS_RoomPresetLibrary`** filters in a fixed order — **capacity** (`slot_count >= edges`) → **tags** (`node.tags ⊆ preset.tags`) → **specificity** (fewest surplus tags) → **weight**. Weight applies *last*, so tuning it does nothing when competitors were already dropped by capacity or tags; that was the standing confusion about `lab_room`/`exit_room` never appearing. `explain_selection()` returns the per-preset rejection reason (same code path as `select_preset`, so the two can't drift) and `validate()`/`validate_preset()` check `slot_count` against the scene's real doors, two doors on one wall, and empty/duplicate `slot_id`s. Both exist for the **Генератор** dock.
- **`RunManager`** (autoload) owns one active run. The **streaming granule is a layer** — every node of one `depth` (`RS_LevelGraph.get_nodes_by_depth`) is spawned at once and laid out on a deterministic grid (`_layer_layout`: floors stacked by `FLOOR_SPACING`, rooms of a floor in a row by `ROOM_SPACING`, ordered by `index_in_layer`). Travel inside the layer is a pure teleport; travel to another depth despawns the layer and spawns the new one. Per-room bookkeeping lives in `SpawnedRoom` (entity + nested children + doors). Seed comes from `WorldSave.save.run_seed()` (derived from `world_seed` + `death_count`), so generation is reproducible.
  - Rooms of a floor are **not** laid out in a row: `_plan_layer` places each neighbour in the cell its connecting door points at, so the grid mirrors the graph (see "Doors ↔ graph edges" below).
  - **Room-scene invariant:** the `Doors` container node must be a `Node3D`, not a plain `Node`. Godot's Node3D inherits its transform only from a **direct** Node3D parent — a plain `Node` in between silently detaches doors (and their colliders) from the room, leaving them at the world origin. Harmless while every room sat at the origin; fatal once layers are laid out on a grid.
- **`WorldSave`** persists `RS_WorldSave` to `user://world_save.tres`: `world_seed` + `death_count` (they derive `run_seed()`) plus the run's progress — `run_in_progress`, `current_node_id`, `visited_node_ids`, `lifespan_remaining`. The complex is never serialized room-by-room; it is regenerated from the seed. `RunManager` checkpoints via `WorldSave.record_progress()` on every room change, and `save_progress()` (pause-menu «Сохранить») does it on demand — not redundant, since lifespan ticks continuously between room changes. `finish_run` clears the run, `die` clears it and increments `death_count`, `leave_to_menu` keeps it (you can resume) but **releases the world**. Releasing matters: `RunManager` is an autoload that outlives the scene, so a retained `_rooms` would make the next `enter_complex` treat a layer of freed rooms as already loaded — `enter_complex` therefore also resets streaming state on entry, so every path into a run starts clean. Main-menu **Load** just switches to `world.tscn` (the save is already loaded) and is disabled while `WorldSave.has_save_file` is false.

### Doors ↔ graph edges — read before touching room/door code

Graph edges (`RS_LevelConnection`) and physical room doors are bridged at spawn time, **not** authored by hand:
- Each door is an interactable Entity carrying **`C_DoorSlot { slot_id }`** (stable per-prefab id).
- On spawn, `RunManager._bind_doors` picks the room's `C_DoorSlot` entities (a subset of the already-registered nested entities) and **stamps `C_DoorPortal { target_node_id, locked_by }`** onto each from the node's `connections`, plus the matching `prompt_text` ("Пройти"/"Заперто"). Which edge goes to which door comes from the layer plan — see below. More edges than doors → warning, some nodes unreachable (that's what `gen_verifier` measures).
- Surplus slots (more doors than edges) are **sealed** by `_seal_door`: an empty `C_DoorPortal` (empty `target_node_id` == "sealed") and the prompt "Прохода нет" with `show_key_hint = false`. Interaction stays **enabled** — a disabled `C_Interactable` is skipped by `S_InteractionDetector`, so the door would neither highlight nor explain itself and reads as a bug.
- Traversal goes through the interaction system: `A_TravelThroughDoor` reads its entity's `C_DoorPortal`; a sealed or locked door posts a `C_ScreenMessage` on the player instead of travelling, otherwise it calls `RunManager.travel_to(target_node_id)`. On arrival the player is placed **in front of the door leading back** to where they came from, stepping in perpendicular to that door's wall (`RS_RoomLayout` side) at `SpawnPoint` floor height — and **only the position is written**: yaw lives on `E_Player`, pitch on its camera, and re-aiming a player who opened the door at an angle is disorienting. `SpawnPoint` is the fallback only when the room was not entered through a door (run start, save load).
- **Caveat**: `world.add_entity(room)` registers ONLY the room itself — GECS does not walk the tree for nested `Entity` children. `RunManager` registers **all** nested entities (`Incubator`, doors, …) explicitly via `_register_room_children` and removes them in `_despawn_layer` (per room: `SpawnedRoom.children`, with `SpawnedRoom.doors` as the door subset). Keep that invariant when changing room spawn/despawn. Removal filters `is_instance_valid` first: `RunManager` is an autoload, so after an exit-to-menu the previous run's entity refs are dangling (freed with the old world), and `remove_entity`'s typed param rejects freed objects before its own guard runs.

The geometry convention itself (which wall is "north", which grid cell a door points at) lives in **`RS_RoomLayout`** — one static home shared by `RunManager` (runtime layout) and the **Генератор** dock (scene validation), so the tool can't validate a rule the game doesn't follow.

**Slot↔edge matching follows the physical layout.** `_plan_layer` embeds each floor's graph into a 2D cell grid: a neighbour is placed in the cell the connecting door points at, so walking through the north door lands you in the room that is physically north. A door's side is derived from its **geometry** (`_direction_of_door`: position relative to the room centre), never from `C_DoorSlot.slot_id` — slot ids are stable identifiers only and in `vertical_hub_*` do not match the walls at all. `slot_id` survives purely as a deterministic sort key. Edges that cannot get an adjacent cell (cross-floor `floor_hub`, cross-layer `vertical_hub`, cycle edges, presets with too few doors) fall to a leftover pass that picks the free door pointing closest to the target. Measured across 5 seeds × 5 layers: ~87% of same-floor doors open onto the room actually behind them; the rest is bounded by the preset library (single-door rooms with degree > 1).

## Interaction system (see docs/astral-genesis/how-to/Взаимодействие.md)

An interactable object needs three things: a **`C_Interactable`** component, a collider on the **`interactives` physics layer (layer_4, mask bit 8)**, and either an `interact()` method or `actions[]` of `RS_InteractionAction`. `S_InteractionDetector` raycasts from the player camera each physics frame and walks *up* the node tree from the hit collider to find the owning `Entity` (so the collider may live deep inside an imported scene, not on the Entity itself). It toggles `C_Highlighted`, which drives crosshair growth and the outline observer (`O_OutlineVisual`). Outline only finds meshes that are a `GeometryInstance3D` root or a child named exactly `MeshInstance3D`.

Two distinct text channels — don't conflate them:
- **Prompt** (`hud_prompt.gd`) — persistent while the crosshair is on the object. Shows `C_Interactable.prompt_text`, prefixed with the action key from `InputMap` unless `show_key_hint = false` (for objects that explain themselves but do nothing when pressed).
- **Screen message** (`C_ScreenMessage` → `hud_message.gd`, expired by `S_ScreenMessage`) — a one-off line reacting to a press. Logic attaches the component to the player, the HUD renders it, the system removes it on timeout. Re-showing a message is a **remove + add** (direct field writes don't signal the world, so the HUD would miss the new text).

## Conventions & docs

- Project docs live in `docs/astral-genesis/` (Russian), an Obsidian vault: `Состояние проекта.md` (implemented-state overview), how-to guides (`Взаимодействие.md`, `Цикл забега.md`), lore (`История.md`), and roadmap under `Задачи/`. Read the relevant how-to before reworking doors/graph or interaction.
- Physics layers: 1 `colliders`, 2 `player`, 3 `enemies`, 4 `interactives`. Systems reference these by bit (e.g. body-snatch raycasts only `enemies` = `1 << 2`).
