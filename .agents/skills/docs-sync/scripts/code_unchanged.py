#!/usr/bin/env python3
"""Сторож чистки комментариев: код без комментариев и пустых строк в рабочем
дереве обязан совпасть с ревизией. Чистка не меняет поведения — расхождение
значит, что вместе с комментарием ушёл код.

Использование:
    python code_unchanged.py [--rev HEAD] [пути...]   # по умолчанию — изменённые .gd
Выход 1 и дифф по каждому файлу, где код разошёлся.
"""
from __future__ import annotations

import argparse
import difflib
import subprocess
import sys


def strip_comments(text: str) -> list[str]:
    """Строки кода без комментариев. '#' внутри строковых литералов — не комментарий."""
    out = []
    for line in text.splitlines():
        quote = None
        cut = len(line)
        i = 0
        while i < len(line):
            ch = line[i]
            if quote:
                if ch == "\\":
                    i += 2
                    continue
                if ch == quote:
                    quote = None
            elif ch in "\"'":
                quote = ch
            elif ch == "#":
                cut = i
                break
            i += 1
        code = line[:cut].rstrip()
        if code.strip():
            out.append(code)
    return out


def git(*args: str) -> str:
    return subprocess.run(["git", *args], capture_output=True, text=True, check=True).stdout


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rev", default="HEAD")
    parser.add_argument("paths", nargs="*")
    args = parser.parse_args()
    paths = args.paths or [p for p in git("diff", "--name-only", args.rev).splitlines() if p.endswith(".gd")]

    broken = 0
    for path in paths:
        try:
            before = git("show", f"{args.rev}:{path}")
        except subprocess.CalledProcessError:
            continue  # новый файл — сравнивать не с чем
        after = open(path, encoding="utf-8").read()
        a, b = strip_comments(before), strip_comments(after)
        if a != b:
            broken += 1
            print(f"КОД ИЗМЕНИЛСЯ: {path}")
            sys.stdout.writelines(l + "\n" for l in difflib.unified_diff(a, b, lineterm="", n=1))
    print(f"проверено {len(paths)}, с изменённым кодом {broken}")
    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main())
