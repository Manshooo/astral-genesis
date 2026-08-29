# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

## How to use this file

**This file is a map, not a manual.** It sits in context for the whole session, so it stays deliberately small: a one-paragraph orientation per area plus a link to the real documentation in `docs/astral-genesis/`. **Open the linked doc when you start working on that area** — that is where the mechanics, invariants and rationale live.

**Adding knowledge: the summary and the link go here, the explanation goes in the doc.** Any section here that grows past a few lines belongs in `docs/astral-genesis/` instead. Keeping docs and code comments true to the code is the `docs-sync` skill's job.

## Project

**Astral Genesis** — a first-person roguelike dungeon-crawler set in a post-apocalyptic underground complex. Each run is a procedurally generated graph of rooms rather than a linear level, and the core mechanic is **possessing bodies**: the player cannot survive on their own for long and stays alive by taking over the bodies they find. Grim, muted sci-fi look.

**The project language is Russian.** Documentation, code comments and commit messages are written in Russian — match that language.

Engine specifics (`project.godot`): **Godot 4.7.2**, Forward+, **Jolt Physics** (3D) with physics on a separate thread, Windows renderer forced to **d3d12**.

## Running, testing & building

- **Running the game**: play the project from the Godot editor, or play a scene directly (F6) to skip straight into it. Zed launch configs: `.zed/debug.json` (adapter `godot`).
- **Testing and debugging** is the **`gameplay-testing`** skill's job — it writes and runs the headless checks in `dev/` (`godot --headless <scene>`, they exit nonzero on failure) and carries the manual-playtest checklist. Invoke it rather than reinventing a run command; there is no third-party test framework (GUT/gdUnit) in this project, the checks are plain Godot scenes.
- **Releases are driven by the branch name — the version is never written by hand.** Merging a `release/vX.Y.Z` PR into master derives the number, bumps, tags and publishes it. Never add a manual version bump to a PR; it will be overwritten. Local builds: `dev/release.ps1` → `dist/`. Details: [Релизы и сборка](docs/astral-genesis/how-to/Релизы%20и%20сборка.md).
- **Assets** (`.glb`, `.svg`, images) are tracked via **Git LFS** — see [Конвенции проекта](docs/astral-genesis/Справка/Конвенции%20проекта.md).

## Code style

- **Hard tabs**, LF line endings, UTF-8. Otherwise the official GDScript style guide: `snake_case` members and functions, `PascalCase` classes, `CONSTANT_CASE` constants, `_` prefix for private members and unused parameters.
- **Typed GDScript**: annotate parameters and returns, prefer inferred `:=` for locals.
- **Every script opens with a class-level comment saying why it exists** — a `##` block after `extends` (it reaches Godot's built-in docs) or a `#` header above `class_name`. Two blank lines between top-level functions.
- **Comments explain WHY, never WHAT.** A comment restating what the code already says is noise; a comment recording a hidden invariant, a rejected alternative or a workaround is the point. Comments are in Russian.
- New scripts go through the templates in `src/script_templates/` so the base-class conventions hold.

## Git conventions

- **Branches — everything merges via PR, nothing is committed straight to a long-lived branch.** `master` only changes via PR (branch protection to follow). `release/vX.Y.Z` branches from `master` and drives the release pipeline (see above); merging it back into `master` is a PR too. Feature/fix/docs work (`feat/kebab-case`, `fix/kebab-case`, `docs/kebab-case`, …) branches from the *release* branch, not from `master`, and merges back into that release branch via PR as well — this keeps the release branch's PR history a clean, ready-made changelog for the version.
- **Commit subject**: `Область: что сделано` — Russian, area capitalized, no trailing period. E.g. `Двери: запечённый меш вместо процедурного бокса`. This is not Conventional Commits — do not write `feat:`/`fix:`.
- **Commit body**: Russian prose explaining **why**, grouped in paragraphs by area when a change spans several. Do not list changed files — the diff already does that.
- **Drafting the actual message** — reading a diff and writing it in this project's voice (diagnosis-first for fixes, rejected-alternatives-first for design decisions) is the **`commit-message`** skill's job.

## Architecture at a glance

Each area below is one paragraph of orientation. **Read the linked doc before reworking that area.**

**ECS** — the whole game is built on **GECS** (`addons/gecs/`), a git submodule pinned to `release-v9.2.0`; never edit files under it, they are upstream (`git submodule update --init` after cloning). Components (`C_*`) are pure data, systems (`S_*`) hold all behavior, entities (`E_*`) are containers, observers (`O_*`) react to component changes. The frame loop is driven manually in `src/world/main.gd` over named system groups. Two rules that cause silent breakage when violated: **raycasting systems must live in the `"physics"` group** (Jolt is threaded, space-state is only safe from `_physics_process`), and **structural changes — adding/removing components or entities — must go through the `cmd` buffer, never directly inside `process()`** (systems iterate archetypes zero-copy, so a direct change skips entities); writing component *fields* is unrestricted. Everything else — the full model, «Правило v9» in detail, ECS patterns and pitfalls: [GECS и правила движка](docs/astral-genesis/how-to/GECS%20и%20правила%20движка.md).

**World generation & run flow** — a run is a deterministic **graph** of rooms generated from a seed, streamed a whole layer at a time by the `RunManager` autoload; the save holds the seed and progress, never the rooms, which are regenerated. Physical doors are bound to graph edges at spawn time rather than authored. Which room scene lands on a node is decided by **two independent axes that must never be merged**: structural `tags` («what the room can do» — a hard subset filter plus specificity) and `room_type` («what kind of place it is» — a soft preference from `data/room_type_catalog.tres`, with per-depth ranges). Putting a type into `tags` turns it into a hard requirement and breaks specificity — that is what once stopped `lab_room` from ever appearing. What each tag *means* is written down in a **descriptive-only** dictionary (`data/room_tag_catalog.tres`): the selector never reads it, so a tag missing from it still works — making it authoritative would turn «add a tag» in the editor tools into a silent break. [Цикл забега](docs/astral-genesis/how-to/Цикл%20забега.md).

**Interaction** — an interactable needs a `C_Interactable` component, a collider on the `interactives` layer, and an `interact()` method or interaction-action resources. A raycast from the camera drives highlighting and the on-screen prompt. [Взаимодействие](docs/astral-genesis/how-to/Взаимодействие.md).

**Body-snatching & decay** — the core mechanic. A body's characteristics are **separate components in its scene, not fields on a stat sheet**, so capture and expulsion move them generically — and its **collision shape, eye level and facing come from that same scene**, never from numbers in code; the player's lifespan is one resource held in two pockets (their own and the worn body's). **An ability is a component and each ability is its own system**: a legless body carries no `C_Jump` and never enters the jump system's query, so movement contains no branch on «what am I wearing» anywhere; the soul's own abilities (`C_Flight`, `C_Phasing`) mirror that with `C_SoulTrait` and sleep while embodied. Skills reach mechanics through one rule: **a mechanic reads a computed stat — the author's base plus the soul's modifiers (`C_StatModifiers`) — never the raw field**, so the base is never overwritten and a new skill is a line of data in `data/skill_tree.tres` rather than a patch to the mechanic. [Захват тела](docs/astral-genesis/how-to/Захват%20тела.md).

**Звук** — идёт через **byProd**, событийный аудиодвижок: механика просит событие (`event:/walk`), а что прозвучит — решает проект, собранный в редакторе byProd. Подключён GDExtension-биндингом `addons/byprod` ([godot-byprod](https://github.com/Manshooo/godot-byprod), MIT). Четыре вещи, нарушение которых ломает всё тихо или фатально: **нативный рантайм не входит в репозиторий** (лицензия Madrigal) и его отсутствие обязано означать «нет звука», а не «не запускается» — поэтому `AudioManager` называет классы расширения только строкой через `ClassDB`, никогда идентификатором; **менеджер ровно один на процесс** — второй роняет рантайм segfault'ом, поэтому его владелец автолоад `AudioManager`, а не тот, кому он понадобился; **пауза идёт уровнем тика, и подписку на неё ставит `AudioManager`** — в рантайме она выключена по умолчанию, а разовый звук после `release_when_finished()` игра уже не держит и остановить не может, так что подписать его позже неоткуда; **контент пока пробный** — `assets/sound/demo`, одно событие, и его собранный `build/` обязан лежать в git и в `include_filter` экспорта, иначе сборка молча выходит без звука. Первый потребитель — шаги: `C_Footsteps` это характеристика тела (лежит в его сцене, переносится при захвате), а `S_Footsteps` озвучивает ходьбу тем способом, каким собрано событие: разовым звуком на каждый отмеренный ПУТЁМ, а не временем шаг — либо одной петлёй с параметром темпа. [Звук](docs/astral-genesis/how-to/Звук.md).

**Editor tooling** — `addons/game_design_tool` is the single designer-facing plugin: a main-screen tab «Геймдизайн» holding «Шаблоны» (entity templates), «Редактор пресетов» (room presets and the tag dictionary) and «Генератор мира» (3D layer preview plus the seed sweep), with several non-obvious traps around `@tool` resources, lazy tab building, inspector labels and `Label` tooltips. [Редакторские инструменты](docs/astral-genesis/how-to/Редакторские%20инструменты.md).

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

Autoloads (`src/autoloads/`): `ECS`, `GameConfig`, `SettingsManager`, `SkillManager`, `UIManager`, `WorldSave`, `RunManager`, `AudioManager`. Tunable game data lives as `.tres` under `data/` and is edited in-editor, not hardcoded. Autoload responsibilities, physics layers, the project-wide UI theme and the key-rebinding codec: [Конвенции проекта](docs/astral-genesis/Справка/Конвенции%20проекта.md).

## Документация — карта

`docs/astral-genesis/` is an Obsidian vault (Russian, `[[wikilinks]]`).

| Area | Doc |
|---|---|
| What is actually implemented, subsystem by subsystem | [Состояние проекта](docs/astral-genesis/Состояние%20проекта.md) |
| ECS model, «Правило v9», FSM/pattern knowledge | [GECS и правила движка](docs/astral-genesis/how-to/GECS%20и%20правила%20движка.md) |
| World gen, layer streaming, doors, travel, save/load | [Цикл забега](docs/astral-genesis/how-to/Цикл%20забега.md) |
| Interactables, raycast, prompts, screen messages | [Взаимодействие](docs/astral-genesis/how-to/Взаимодействие.md) |
| Capture/expel, body traits, decay model, `E_Body` contract | [Захват тела](docs/astral-genesis/how-to/Захват%20тела.md) |
| Editor tooling traps, template authoring | [Редакторские инструменты](docs/astral-genesis/how-to/Редакторские%20инструменты.md) |
| byProd, единственность менеджера, пауза, шаги | [Звук](docs/astral-genesis/how-to/Звук.md) |
| Physics layers, UI theme, prefixes, rebinding codec | [Конвенции проекта](docs/astral-genesis/Справка/Конвенции%20проекта.md) |
| CI, versioning, local and manual releases | [Релизы и сборка](docs/astral-genesis/how-to/Релизы%20и%20сборка.md) |
| Controls, player-facing | [Управление](docs/astral-genesis/Справка/Управление.md) |
| Lore | [История](docs/astral-genesis/История.md) |
| Roadmap, task cards | `docs/astral-genesis/Задачи/` |

Four skills maintain and exercise all of the above: **`docs-sync`** (keep docs, code comments and this map true to the code), **`gameplay-testing`** (write and run the headless checks, plus the playtest checklist), **`commit-message`** (draft commit messages in the project's actual voice), and **`project-status`** (what's in progress, what's planned, what loose ends remain — calls `docs-sync` for the documentation side).
