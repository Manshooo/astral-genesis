"""Physics layer names, read out of the Godot project.

Godot stores them in project.godot under [layer_names] as
`3d_physics/layer_N="name"`.  Blender's LAYER widget is a nameless grid of 32
squares, which means picking a layer here has always been a matter of counting
cells and remembering which one is "interactives".  Reading the names turns that
into labelled toggles, and — more importantly — a layer renamed in Godot shows
up renamed in Blender instead of quietly meaning something else.

The file is re-read whenever its mtime changes, so nothing has to be refreshed
by hand after editing the project settings.
"""

import os
import re

# Godot's own limit; CollisionObject3D.collision_layer is a 32-bit mask.
LAYER_COUNT = 32

_PATTERN = re.compile(r'^\s*3d_physics/layer_(\d+)\s*=\s*"(.*)"\s*$')

# (path, mtime) -> [name or "" per layer].  Redraws hit this every frame, so the
# parse has to happen once per actual change, not once per draw.
_CACHE = {}


def _parse(path: str):
    names = [""] * LAYER_COUNT
    section = False
    try:
        with open(path, "r", encoding="utf-8") as handle:
            for line in handle:
                stripped = line.strip()
                if stripped.startswith("["):
                    section = stripped == "[layer_names]"
                    continue
                if not section:
                    continue
                match = _PATTERN.match(line)
                if match:
                    index = int(match.group(1)) - 1
                    if 0 <= index < LAYER_COUNT:
                        names[index] = match.group(2)
    except OSError:
        return [""] * LAYER_COUNT
    return names


def physics_layers(root: str):
    """Layer names of the project at `root`, index 0 being Godot's layer 1.

    Always returns 32 entries; an unnamed layer is an empty string.
    """
    if not root:
        return [""] * LAYER_COUNT
    path = os.path.join(root, "project.godot")
    try:
        stamp = os.path.getmtime(path)
    except OSError:
        return [""] * LAYER_COUNT

    key = (path, stamp)
    cached = _CACHE.get(key)
    if cached is None:
        cached = _parse(path)
        _CACHE.clear()          # only the current version of one project matters
        _CACHE[key] = cached
    return cached


def named_indices(names):
    """Indices of the layers that actually carry a name."""
    return [index for index, name in enumerate(names) if name]


def label(names, index: int) -> str:
    """Human label for one layer: its name, or «Layer N» when it has none."""
    if 0 <= index < len(names) and names[index]:
        return names[index]
    return "Layer %d" % (index + 1)


def describe(names, mask: int) -> str:
    """Comma-separated names of the layers set in `mask`, for reports."""
    parts = [label(names, index) for index in range(LAYER_COUNT) if mask & (1 << index)]
    return ", ".join(parts) if parts else "none"
