"""Path helpers around the Godot project root.

Everything the pipeline writes is addressed relative to the folder containing
project.godot, so that .blend files and the game repo can live anywhere.
"""

import os

import bpy


def find_project_root(start: str) -> str:
    """Walk up from `start` looking for project.godot. Returns "" if not found."""
    if not start:
        return ""
    path = os.path.abspath(start)
    if os.path.isfile(path):
        path = os.path.dirname(path)
    last = None
    while path and path != last:
        if os.path.isfile(os.path.join(path, "project.godot")):
            return path
        last = path
        path = os.path.dirname(path)
    return ""


# Переменная проекта Blender (5.3+): исходники лежат в своём арт-репозитории, вне
# Godot-проекта, а настройка аддона одна на все проекты Blender этой машины.
PROJECT_VARIABLE = "godot_project"
PROJECT_ROOT_TOKEN = "{project_root}"

SOURCE_PREFERENCES = "add-on preferences"
SOURCE_BLENDER_PROJECT = "Blender project variable"
SOURCE_BLEND_LOCATION = "search from the .blend"


def blender_project_root(project=None) -> str:
    """Godot root from the active Blender project's variable, or "" (no project, no variable, before 5.3)."""
    if project is None:
        project = getattr(bpy.data, "project", None)
    if project is None:
        return ""
    variable = next((v for v in project.variables if v.name == PROJECT_VARIABLE), None)
    value = getattr(variable, "value", "") if variable is not None else ""
    if not isinstance(value, str) or not value.strip():
        return ""
    base = project.root_path
    value = value.strip().replace(PROJECT_ROOT_TOKEN, base)
    if not os.path.isabs(value):
        value = os.path.join(base, value)
    return os.path.normpath(value)


def resolve_project_root(prefs):
    """(root, source): the add-on setting wins, then the Blender project, then a search up from the .blend."""
    configured = bpy.path.abspath(prefs.godot_project) if prefs.godot_project else ""
    if configured and os.path.isdir(configured):
        return os.path.normpath(configured), SOURCE_PREFERENCES
    from_project = blender_project_root()
    if from_project:
        return from_project, SOURCE_BLENDER_PROJECT
    return find_project_root(bpy.data.filepath), SOURCE_BLEND_LOCATION


def project_root(prefs) -> str:
    return resolve_project_root(prefs)[0]


def is_valid_project(root: str) -> bool:
    return bool(root) and os.path.isfile(os.path.join(root, "project.godot"))


def rel_to_res(root: str, abs_path: str) -> str:
    """Convert an absolute path into a res:// path, or "" when outside the project."""
    if not root:
        return ""
    try:
        rel = os.path.relpath(os.path.abspath(abs_path), root)
    except ValueError:  # different drives on Windows
        return ""
    if rel.startswith(".."):
        return ""
    return "res://" + rel.replace(os.sep, "/")


def res_to_abs(root: str, res_path: str) -> str:
    if not res_path.startswith("res://"):
        return res_path
    return os.path.join(root, res_path[len("res://"):].replace("/", os.sep))


def clean_rel_dir(value: str) -> str:
    """Normalise a user-typed relative folder: no leading slash, forward slashes, no res://."""
    value = (value or "").strip().replace("\\", "/")
    if value.startswith("res://"):
        value = value[len("res://"):]
    return value.strip("/")


def ensure_dir(path: str):
    if path and not os.path.isdir(path):
        os.makedirs(path, exist_ok=True)
