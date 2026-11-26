#!/usr/bin/env python3
"""Находит в GDScript комментарии, которые по правилу проекта должны жить в
вики, а не в коде: длинные блоки и файлы, где комментариев больше, чем кода.

Не автофикс и не вердикт. Длинный блок бывает честной ловушкой движка в трёх
строках, а короткий — пересказом кода; список — очередь на чтение глазами по
порядку из SKILL.md («Комментарии: что остаётся в коде»).

Использование:
    python comment_audit.py [пути...] [--block N] [--ratio R] [--top K]

По умолчанию — src/ и addons/game_design_tool/, блоки длиннее 3 строк, файлы с
долей комментариев выше 0.25.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

COMMENT_RE = re.compile(r"^\s*#")
DEFAULT_ROOTS = ["src", "addons/game_design_tool"]


def blocks(lines: list[str]) -> list[tuple[int, int]]:
    """Сплошные блоки строк-комментариев: (первая строка 1-based, длина)."""
    out: list[tuple[int, int]] = []
    start = None
    for i, line in enumerate(lines):
        if COMMENT_RE.match(line):
            if start is None:
                start = i
        elif start is not None:
            out.append((start + 1, i - start))
            start = None
    if start is not None:
        out.append((start + 1, len(lines) - start))
    return out


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="*")
    parser.add_argument("--block", type=int, default=3, help="порог длины блока, строк")
    parser.add_argument("--ratio", type=float, default=0.25, help="порог доли комментариев в файле")
    parser.add_argument("--top", type=int, default=40, help="сколько файлов показать")
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[4]
    targets = [root / p for p in (args.paths or DEFAULT_ROOTS)]
    files = [f for t in targets for f in (t.rglob("*.gd") if t.is_dir() else [t])]

    report = []
    total_comment = total_code = 0
    for f in files:
        lines = f.read_text(encoding="utf-8").splitlines()
        code = [l for l in lines if l.strip()]
        comment = [l for l in code if COMMENT_RE.match(l)]
        total_comment += len(comment)
        total_code += len(code)
        long_blocks = [b for b in blocks(lines) if b[1] > args.block]
        ratio = len(comment) / max(len(code), 1)
        if long_blocks or ratio > args.ratio:
            report.append((sum(b[1] for b in long_blocks), ratio, f, long_blocks))

    report.sort(key=lambda r: (-r[0], -r[1]))
    for excess, ratio, f, long_blocks in report[: args.top]:
        where = ", ".join(f"{start}+{n}" for start, n in long_blocks[:6])
        more = f" … ещё {len(long_blocks) - 6}" if len(long_blocks) > 6 else ""
        print(f"{excess:4d} строк в длинных блоках, доля {ratio:.2f}  {f.relative_to(root)}  [{where}{more}]")
    print(f"\nвсего: {total_comment} строк комментариев на {total_code} непустых "
          f"({total_comment / max(total_code, 1):.0%}), файлов к разбору: {len(report)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
