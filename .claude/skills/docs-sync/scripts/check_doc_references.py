#!/usr/bin/env python3
"""Ищет в документации ссылки на код, которого больше нет.

Сканирует CLAUDE.md и docs/astral-genesis/**/*.md (кроме .obsidian/) на
обратные кавычки вида `C_Foo`, `S_Foo.bar()`, `RS_Foo`, а также на пути файлов
(`src/entities/body/e_body.tscn`). Идентификатор без единого совпадения в
src/ или addons/ (кроме addons/gecs — апстрим-сабмодуль), либо путь, которого
нет на диске, — вероятно, устарел после переименования/удаления.

Не автофикс: регулярка ловит и случайные совпадения (например, обычные слова
в обратных кавычках) — список нужно проверить глазами, а не применять слепо.

По умолчанию пропускает docs/astral-genesis/Задачи/ (роадмап намеренно
описывает ещё не реализованный код) — добавить --include-roadmap, чтобы
включить и его.

Два источника ожидаемого шума, которые НЕ являются устареванием:
  - «GECS и правила движка.md», разделы про FSM и example_card_game —
    гипотетические имена (C_Idle, C_State) и компоненты внешнего
    репозитория-примера (C_Phase, C_Match, …), а не нашего кода;
  - упоминания ещё не написанных систем в разделах «пробелы»/«планы»
    (например S_EnemyAI в «Состояние проекта.md»).

Использование:
    python check_doc_references.py [--include-roadmap]
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

IDENT_RE = re.compile(r"\b(?:C|S|E|O|A|RS)_[A-Za-z0-9_]+\b")
BACKTICK_RE = re.compile(r"`([^`\n]+)`")
PATH_LIKE_RE = re.compile(
    r"^[\w./\\-]+\.(?:gd|tscn|tres|glb|svg|png|jpg|jpeg|md|json|cfg)$"
)
EXCLUDED_CODE_PARTS = {"gecs"}  # апстрим-сабмодуль, не наш код


def find_repo_root(start: Path) -> Path:
    for candidate in (start, *start.parents):
        if (candidate / "project.godot").exists():
            return candidate
    raise SystemExit("Не найден project.godot — запускать внутри репозитория")


def collect_doc_files(repo_root: Path, include_roadmap: bool) -> list[Path]:
    docs = [repo_root / "CLAUDE.md"]
    vault = repo_root / "docs" / "astral-genesis"
    roadmap = vault / "Задачи"
    for path in sorted(vault.rglob("*.md")):
        if ".obsidian" in path.parts:
            continue
        if not include_roadmap and roadmap in path.parents:
            continue
        docs.append(path)
    return [d for d in docs if d.exists()]


def collect_code_text(repo_root: Path) -> str:
    blobs: list[str] = []
    for base in (repo_root / "src", repo_root / "addons"):
        if not base.exists():
            continue
        for path in base.rglob("*.gd"):
            if EXCLUDED_CODE_PARTS & set(path.parts):
                continue
            try:
                blobs.append(path.read_text(encoding="utf-8", errors="ignore"))
            except OSError:
                continue
    return "\n".join(blobs)


def check_identifiers(
    doc_files: list[Path], code_blob: str, repo_root: Path
) -> dict[str, list[tuple[int, str]]]:
    stale: dict[str, list[tuple[int, str]]] = {}
    for doc in doc_files:
        text = doc.read_text(encoding="utf-8", errors="ignore")
        rel = str(doc.relative_to(repo_root))
        for lineno, line in enumerate(text.splitlines(), 1):
            for match in BACKTICK_RE.finditer(line):
                token = match.group(1)
                for ident in dict.fromkeys(IDENT_RE.findall(token)):
                    base = ident.split(".")[0]
                    pattern = re.compile(r"\b" + re.escape(base) + r"\b")
                    if not pattern.search(code_blob):
                        stale.setdefault(rel, []).append((lineno, ident))
    return stale


def check_paths(
    doc_files: list[Path], repo_root: Path
) -> dict[str, list[tuple[int, str]]]:
    missing: dict[str, list[tuple[int, str]]] = {}
    for doc in doc_files:
        text = doc.read_text(encoding="utf-8", errors="ignore")
        rel = str(doc.relative_to(repo_root))
        for lineno, line in enumerate(text.splitlines(), 1):
            for match in BACKTICK_RE.finditer(line):
                token = match.group(1).strip()
                if "/" not in token and "\\" not in token:
                    continue
                if not PATH_LIKE_RE.match(token):
                    continue
                from_root = (repo_root / token).resolve()
                from_doc = (doc.parent / token).resolve()
                if not from_root.exists() and not from_doc.exists():
                    missing.setdefault(rel, []).append((lineno, token))
    return missing


def check_wikilinks(repo_root: Path) -> dict[str, list[tuple[int, str]]]:
    """Битые [[wikilinks]] внутри вики.

    Obsidian не роняет ошибку на ссылке в никуда — она просто красится другим
    цветом, поэтому переименование файла тихо рвёт ссылки на него. Роадмап здесь
    НЕ пропускаем: карточки ссылаются друг на друга, и битая ссылка между ними —
    настоящая опечатка, а не «код ещё не написан».
    """
    vault = repo_root / "docs" / "astral-genesis"
    if not vault.exists():
        return {}
    notes = {
        p.stem for p in vault.rglob("*.md") if ".obsidian" not in p.parts
    }
    broken: dict[str, list[tuple[int, str]]] = {}
    for path in sorted(vault.rglob("*.md")):
        if ".obsidian" in path.parts:
            continue
        rel = str(path.relative_to(repo_root))
        text = path.read_text(encoding="utf-8", errors="ignore")
        for lineno, line in enumerate(text.splitlines(), 1):
            # Перенос строки внутри [[...]] Obsidian не понимает, поэтому
            # ссылку ищем построчно — «незакрытая» ссылка так и всплывёт.
            for match in re.finditer(r"\[\[([^\]|#\n]+)", line):
                name = match.group(1).strip()
                if name and name not in notes:
                    broken.setdefault(rel, []).append((lineno, name))
    return broken


def main() -> int:
    include_roadmap = "--include-roadmap" in sys.argv
    repo_root = find_repo_root(Path(__file__).resolve())
    doc_files = collect_doc_files(repo_root, include_roadmap)
    code_blob = collect_code_text(repo_root)

    stale_idents = check_identifiers(doc_files, code_blob, repo_root)
    missing_paths = check_paths(doc_files, repo_root)
    broken_links = check_wikilinks(repo_root)

    if not stale_idents and not missing_paths and not broken_links:
        print("Ссылки в документации не расходятся с кодом.")
        return 0

    if stale_idents:
        print(
            "Возможно устаревшие идентификаторы "
            "(не найдены в src/, addons/ кроме gecs):"
        )
        for doc, items in stale_idents.items():
            for lineno, ident in items:
                print(f"  {doc}:{lineno}  `{ident}`")

    if missing_paths:
        print("\nПути, которых нет на диске:")
        for doc, items in missing_paths.items():
            for lineno, token in items:
                print(f"  {doc}:{lineno}  `{token}`")

    if broken_links:
        print("\nБитые [[wikilinks]] (нет такой заметки в вики):")
        for doc, items in broken_links.items():
            for lineno, name in items:
                print(f"  {doc}:{lineno}  [[{name}]]")

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
