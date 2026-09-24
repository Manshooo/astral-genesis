"""Godot import hints, expressed as name suffixes.

Godot's scene importer reads suffixes off *node names*, so every hint here is
applied by temporarily renaming the Blender datablock right before the glTF
export and restoring the original name afterwards.  Storing hints as properties
instead of baking them into names keeps the .blend readable and makes the hints
survive renames.

Suffix list mirrors Godot 4.7 "Node type customization using name suffixes".
"""

import re
from contextlib import contextmanager

# --- object-level suffixes -------------------------------------------------

COLLISION_ITEMS = [
    ('NONE', "None", "Export the mesh as-is, no collision generated", 0),
    ('COL', "-col (mesh + trimesh)", "Keep the visual mesh, add a StaticBody3D child with a ConcavePolygonShape3D", 1),
    ('CONVCOL', "-convcol (mesh + convex)", "Keep the visual mesh, add a StaticBody3D child with a ConvexPolygonShape3D", 2),
    ('COLONLY', "-colonly (trimesh only)", "Replace the mesh with a StaticBody3D + ConcavePolygonShape3D. Visual mesh is discarded", 3),
    ('CONVCOLONLY', "-convcolonly (convex only)", "Replace the mesh with a StaticBody3D + ConvexPolygonShape3D. Visual mesh is discarded", 4),
    ('RIGID', "-rigid (RigidBody3D)", "Import the mesh as a RigidBody3D with generated collision", 5),
    ('VEHICLE', "-vehicle", "Import the mesh as a child of a VehicleBody3D", 6),
    ('WHEEL', "-wheel", "Import the mesh as a child of a VehicleWheel3D", 7),
    ('NAVMESH', "-navmesh", "Convert the mesh into a NavigationRegion3D navigation mesh (visual mesh is discarded)", 8),
    ('OCC', "-occ (mesh + occluder)", "Keep the visual mesh and add an OccluderInstance3D", 9),
    ('OCCONLY', "-occonly (occluder only)", "Convert the mesh into an OccluderInstance3D", 10),
    ('NOIMP', "-noimp (skip)", "Remove this node at import time. Use for helpers, references, blockout geometry", 11),
]

COLLISION_SUFFIX = {
    'NONE': "",
    'COL': "-col",
    'CONVCOL': "-convcol",
    'COLONLY': "-colonly",
    'CONVCOLONLY': "-convcolonly",
    'RIGID': "-rigid",
    'VEHICLE': "-vehicle",
    'WHEEL': "-wheel",
    'NAVMESH': "-navmesh",
    'OCC': "-occ",
    'OCCONLY': "-occonly",
    'NOIMP': "-noimp",
}

# Every word Godot looks for at the end of a *node* name.  Taken from the
# _teststr() call sites in editor/import/3d/resource_importer_scene.cpp rather
# than from the manual, because the manual omits the separator rules below.
GODOT_NODE_SUFFIX_WORDS = (
    "convcolonly", "colonly", "convcol", "col",
    "occonly", "occ", "navmesh", "rigid", "vehicle", "wheel", "noimp",
)

# --- material-level suffixes ----------------------------------------------

MATERIAL_SUFFIXES = {
    'alpha': "-alpha",   # forces BaseMaterial3D TRANSPARENCY_ALPHA
    'vcol': "-vcol",     # enables vertex color use on the material
}

GODOT_MATERIAL_SUFFIX_WORDS = ("alpha", "vcol")

# --- animation-level suffixes ---------------------------------------------

ANIM_SUFFIXES = {
    'loop': "-loop",
    'cycle': "-cycle",
}

GODOT_ANIM_SUFFIX_WORDS = ("loop_mode", "loop", "cycle")

# Characters Godot strips from node names (String::validate_node_name).
INVALID_NODE_CHARS = '.:@/"%'


def sanitize_node_name(name: str) -> str:
    """Return `name` with characters Godot would strip replaced by '_'."""
    return "".join('_' if c in INVALID_NODE_CHARS else c for c in name)


def sanitize_file_name(name: str) -> str:
    out = []
    for c in name:
        out.append(c if (c.isalnum() or c in "._- ") else '_')
    return "".join(out).strip().replace(" ", "_")


# --- reading Godot's suffixes back off a name ------------------------------
#
# Ported from _teststr()/_fixstr() in resource_importer_scene.cpp, because the
# manual only documents the "-suffix" form.  Godot actually accepts three:
#
#   name-col        trailing, "-" separator
#   name_col        trailing, "_" separator
#   name$colFoo     "$" form, matched *anywhere* in the name
#
# all case-insensitive, and all tested only after a trailing run of digits,
# whitespace and underscores has been ignored (Godot compensates there for
# ".001" duplicate markers whose dot became an underscore on export).

_DUPLICATE_MARKER = re.compile(r"\.\d{3}$")


def _split_duplicate_marker(name: str):
    """Split Blender's own ".001" duplicate marker off the end."""
    match = _DUPLICATE_MARKER.search(name)
    if match:
        return name[:match.start()], match.group(0)
    return name, ""


def _split_numeric_tail(name: str):
    """Split the trailing digits/space/underscore run Godot ignores when matching."""
    index = len(name)
    while index and (name[index - 1].isdigit()
                     or ord(name[index - 1]) <= 32
                     or name[index - 1] == "_"):
        index -= 1
    return name[:index], name[index:]


def _strip_one_suffix(name: str, words) -> str:
    """Remove at most one Godot suffix, the same way _fixstr does."""
    core, tail = _split_numeric_tail(name)
    low = core.lower()
    for word in sorted(words, key=len, reverse=True):
        token = "$" + word
        index = low.find(token)
        if index >= 0:
            return core[:index] + core[index + len(token):] + tail
        for separator in ("-", "_"):
            if low.endswith(separator + word):
                return core[:len(core) - len(word) - 1] + tail
    return name


def find_godot_suffix(name: str, words=GODOT_NODE_SUFFIX_WORDS) -> str:
    """The suffix word Godot would read off `name`, or "" if there is none."""
    base = _split_duplicate_marker(name)[0]
    core = _split_numeric_tail(base)[0]
    low = core.lower()
    for word in sorted(words, key=len, reverse=True):
        if ("$" + word) in low or low.endswith("-" + word) or low.endswith("_" + word):
            return word
    return ""


def strip_godot_suffixes(name: str, words=GODOT_NODE_SUFFIX_WORDS,
                         keep_duplicate_marker: bool = True) -> str:
    """`name` with every Godot import hint removed.

    Loops because a name can legitimately carry more than one hint, and falls
    back to the original when stripping would leave nothing behind.
    """
    base, marker = _split_duplicate_marker(name)
    for _ in range(len(words)):
        stripped = _strip_one_suffix(base, words)
        if stripped == base:
            break
        base = stripped
    base = base.strip(" \t")
    if not base:
        return name
    return base + (marker if keep_duplicate_marker else "")


def has_manual_suffix(name: str) -> str:
    """Display form of the suffix already typed into `name`, or ""."""
    word = find_godot_suffix(name)
    return "-" + word if word else ""


def object_export_name(obj, settings) -> str:
    """Final node name for `obj`, hints included."""
    base = settings.export_name.strip() or obj.name
    base = sanitize_node_name(base)
    suffix = COLLISION_SUFFIX.get(settings.collision, "")
    return base + suffix


def material_export_name(mat, settings) -> str:
    base = sanitize_node_name(mat.name)
    if settings.force_alpha:
        base += MATERIAL_SUFFIXES['alpha']
    if settings.use_vertex_color:
        base += MATERIAL_SUFFIXES['vcol']
    return base


@contextmanager
def renamed(pairs):
    """Temporarily rename datablocks.

    `pairs` is an iterable of (datablock, new_name).  Blender silently appends
    ".001" when a name is taken, so the caller gets back a list of collisions
    to report instead of shipping a wrongly named node to Godot.
    """
    originals = []
    collisions = []
    try:
        for db, new_name in pairs:
            if not new_name or db.name == new_name:
                continue
            originals.append((db, db.name))
            db.name = new_name
            if db.name != new_name:
                collisions.append((new_name, db.name))
        yield collisions
    finally:
        # Restore in reverse so freed-up names are available again.
        for db, old_name in reversed(originals):
            try:
                db.name = old_name
            except ReferenceError:
                pass
