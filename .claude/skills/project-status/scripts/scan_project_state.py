#!/usr/bin/env python3
"""Собирает срез состояния Astral Genesis из четырёх источников:

  1. git — на чём стоим прямо сейчас (ветка, расхождение с origin,
     незакоммиченное, стэши).
  2. Kanban-доска текущей версии (docs/astral-genesis/Задачи/vX.Y.Z.md) —
     колонки «К выполнению» / «В работе» / «Тестирование» / «Готово».
  3. Код — literal TODO/FIXME/XXX-комментарии (высокая точность; слова вроде
     "placeholder" в этом проекте часто законный термин архитектуры, не
     недоделка, поэтому в широкий скан не берутся).
  4. Документация — раздел «Известные пробелы» в Состояние проекта.md, плюс
     (если рядом есть скилл docs-sync) его чек `check_doc_references.py`.

Не чинит и не решает — только собирает то, что разбросано по четырём местам,
в один читаемый срез. Использование:

    python scan_project_state.py [--skip-doc-check]
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path


def find_repo_root(start: Path) -> Path:
    for candidate in (start, *start.parents):
        if (candidate / "project.godot").exists():
            return candidate
    raise SystemExit("Не найден project.godot — запускать внутри репозитория")


def run(cmd: list[str], cwd: Path) -> str:
    result = subprocess.run(
        cmd, cwd=cwd, capture_output=True, text=True, encoding="utf-8", errors="ignore"
    )
    return (result.stdout or "") + (result.stderr or "")


def section_git(repo_root: Path) -> None:
    print("=" * 70)
    print("GIT — на чём стоим")
    print("=" * 70)

    branch = run(["git", "branch", "--show-current"], repo_root).strip()
    print(f"Ветка: {branch or '(detached HEAD)'}")

    tracking = run(
        ["git", "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"],
        repo_root,
    ).strip()
    if tracking and not tracking.startswith("fatal"):
        counts = run(
            ["git", "rev-list", "--left-right", "--count", f"{tracking}...HEAD"],
            repo_root,
        ).split()
        if len(counts) == 2:
            behind, ahead = counts
            if behind == "0" and ahead == "0":
                print(f"В синхроне с {tracking}.")
            else:
                print(f"Относительно {tracking}: впереди {ahead}, позади {behind}.")
                if int(behind) > 0:
                    print(
                        "  -> есть чужие коммиты, которых нет локально — "
                        "перед push стоит git fetch и посмотреть, что там."
                    )
    else:
        print("Ветка не отслеживает upstream (или он недоступен) — сверка с origin пропущена.")

    status = run(["git", "status", "--short"], repo_root).rstrip("\n")
    if status:
        print("\nНезакоммиченные изменения:")
        for line in status.splitlines():
            print(f"  {line}")
    else:
        print("\nРабочее дерево чистое.")

    stash = run(["git", "stash", "list"], repo_root).rstrip("\n")
    if stash:
        print("\nСтэши (забытая работа?):")
        for line in stash.splitlines():
            print(f"  {line}")

    log = run(
        ["git", "log", "-8", "--pretty=format:  %h %s"], repo_root
    ).rstrip("\n")
    print("\nПоследние коммиты:")
    print(log)


def section_kanban(repo_root: Path, branch_hint: str) -> None:
    print("\n" + "=" * 70)
    print("РОАДМАП — доска текущей версии")
    print("=" * 70)

    tasks_dir = repo_root / "docs" / "astral-genesis" / "Задачи"
    m = re.search(r"release/v(\d+\.\d+\.\d+)", branch_hint)
    board_path = None
    if m:
        candidate = tasks_dir / f"v{m.group(1)}.md"
        if candidate.exists():
            board_path = candidate

    if board_path is None:
        available = sorted(p.name for p in tasks_dir.glob("v*.md"))
        print(
            f"Не удалось определить версию по имени ветки «{branch_hint}». "
            f"Доски в Задачи/: {', '.join(available) or '(нет)'}"
        )
        return

    print(f"Доска: {board_path.relative_to(repo_root)}\n")
    text = board_path.read_text(encoding="utf-8")

    # Kanban-плагин Obsidian: h2-заголовок = колонка, "- [ ]"/"- [x]" ниже —
    # карточки, до следующего h2 или "%% kanban:settings".
    sections: dict[str, list[str]] = {}
    current = None
    for line in text.splitlines():
        h2 = re.match(r"^##\s+(.+)$", line)
        if h2:
            current = h2.group(1).strip()
            sections[current] = []
            continue
        if line.strip().startswith("%%"):
            current = None
            continue
        if current is not None and re.match(r"^\s*-\s*\[[ xX]\]", line):
            sections[current].append(line.strip())

    for name, items in sections.items():
        done = sum(1 for i in items if re.match(r"^-\s*\[[xX]\]", i))
        print(f"### {name} ({done}/{len(items)} отмечено)")
        if not items:
            print("  (пусто)")
        for item in items:
            print(f"  {item}")
        print()


def section_code_todos(repo_root: Path) -> None:
    print("=" * 70)
    print("КОД — явные TODO/FIXME")
    print("=" * 70)

    pattern = re.compile(r"#.*\b(TODO|FIXME|XXX)\b", re.IGNORECASE)
    found = False
    for base in (repo_root / "src", repo_root / "dev", repo_root / "addons"):
        if not base.exists():
            continue
        for path in sorted(base.rglob("*.gd")):
            if "gecs" in path.parts:
                continue
            try:
                lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
            except OSError:
                continue
            for lineno, line in enumerate(lines, 1):
                if pattern.search(line):
                    found = True
                    print(f"  {path.relative_to(repo_root)}:{lineno}  {line.strip()}")
    if not found:
        print("  Явных TODO/FIXME/XXX в src/, dev/, addons/ (кроме gecs) нет.")
    print(
        "\nСлова вроде «placeholder»/«черновой» в остальном коде сюда намеренно "
        "не попадают — в этом проекте это часто законный термин (см. "
        "RS_LevelGraph.PLACEHOLDER_ROOM_SCENE), а не флаг недоделки. Такие "
        "места видно по контексту при чтении, не по grep'у."
    )


def section_doc_gaps(repo_root: Path) -> None:
    print("\n" + "=" * 70)
    print("ДОКУМЕНТАЦИЯ — что сама вики называет незакрытым")
    print("=" * 70)

    state_doc = repo_root / "docs" / "astral-genesis" / "Состояние проекта.md"
    if not state_doc.exists():
        print("  Состояние проекта.md не найден.")
        return

    text = state_doc.read_text(encoding="utf-8")
    lines = text.splitlines()
    in_gaps = False
    printed_any = False
    for line in lines:
        h2 = re.match(r"^##\s+(.+)$", line)
        if h2:
            in_gaps = "пробел" in h2.group(1).lower()
            if in_gaps:
                print(f"Раздел «{h2.group(1).strip()}» из Состояние проекта.md:\n")
            continue
        if in_gaps and line.strip().startswith("- "):
            print(f"  {line.strip()}")
            printed_any = True
    if not printed_any:
        print("  Раздел «Известные пробелы» не найден или пуст — проверить вручную.")


def section_docs_sync(repo_root: Path, skip: bool) -> None:
    print("\n" + "=" * 70)
    print("СВЕРКА С КОДОМ — docs-sync")
    print("=" * 70)
    if skip:
        print("  Пропущено (--skip-doc-check).")
        return

    checker = (
        repo_root / ".claude" / "skills" / "docs-sync" / "scripts" / "check_doc_references.py"
    )
    if not checker.exists():
        print("  Скилл docs-sync не найден рядом — сверка недоступна.")
        return

    output = run([sys.executable, str(checker)], repo_root)
    print(output.rstrip("\n"))


def main() -> int:
    skip_doc_check = "--skip-doc-check" in sys.argv
    repo_root = find_repo_root(Path(__file__).resolve())

    section_git(repo_root)
    branch = run(["git", "branch", "--show-current"], repo_root).strip()
    section_kanban(repo_root, branch)
    section_code_todos(repo_root)
    section_doc_gaps(repo_root)
    section_docs_sync(repo_root, skip_doc_check)

    print("\n" + "=" * 70)
    print(
        "Это срез, не диагноз: что в работе/запланировано/недоделано решает "
        "человек, скрипт только сводит источники в одно место."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
