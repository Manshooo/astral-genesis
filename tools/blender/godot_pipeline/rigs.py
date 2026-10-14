"""Контракт рига персонажа: тип рига коллекции и эталонные имена костей.

Одна схема имён на тип рига — на этом держится общая библиотека клипов: тела
одного типа делят её без ретаргетинга, а трек анимации находит кость по имени.
Кость, названная мимо схемы, в Godot не падает — клип просто молча её не
двигает. Поэтому имена сверяются здесь, до экспорта, с эталоном рядом с
аддоном (rigs/<тип>.json), а не по памяти художника.

Эталоны — данные, а не код: имена взяты из SkeletonProfileHumanoid Godot, и
правка схемы не должна требовать правки валидатора.
"""

import json
import os
import re

RIG_TYPE_ITEMS = [
    ('NONE', "Not a character", "No rig contract: props, rooms, animation libraries", 0),
    ('HUMANOID', "Humanoid", "Two legs, two arms (walker). Bone names from rigs/humanoid.json", 1),
    ('CRAWLER', "Crawler", "Upper body only (crawler). Bone names from rigs/crawler.json", 2),
    ('QUADRUPED', "Quadruped", "Four legs and a tail (hound). Bone names from rigs/quadruped.json", 3),
]

# Голова и руки облика — отдельные объекты: пока облик надет на игрока, они
# рисуются только тенью, а меш целиком так не переключить. Суффикс, а не
# свойство: имя объекта доезжает до Godot именем узла, и облику на риге не нужно
# разбирать extras, чтобы найти их.
HEAD_SUFFIX = "_head"
ARMS_SUFFIX = "_arms"

# Автосуффикс Blender для дубля: arm.001.l, leg.001. В Godot такие имена в путях
# треков «плывут» на реимпорте (godotengine/godot#115792).
DUPLICATE_MARKER = re.compile(r"\.\d{3}(?![0-9])")

_FOLDER = os.path.join(os.path.dirname(__file__), "rigs")
_cache = {}


class RigSchema:
    __slots__ = ("rig_type", "required", "allowed")

    def __init__(self, rig_type, required, optional):
        self.rig_type = rig_type
        self.required = tuple(required)
        self.allowed = frozenset(required) | frozenset(optional)


def schema_path(rig_type):
    return os.path.join(_FOLDER, rig_type.lower() + ".json")


def schema(rig_type):
    """Эталон типа рига или None для 'NONE'. Перечитывается по mtime файла."""
    if rig_type == 'NONE':
        return None
    path = schema_path(rig_type)
    mtime = os.path.getmtime(path)
    cached = _cache.get(rig_type)
    if cached is not None and cached[0] == mtime:
        return cached[1]
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    loaded = RigSchema(data["rig_type"], data["required"], data.get("optional", ()))
    _cache[rig_type] = (mtime, loaded)
    return loaded
