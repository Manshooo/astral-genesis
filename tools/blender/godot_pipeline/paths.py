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


def project_root(prefs) -> str:
    """Configured Godot project root, or one auto-detected from the .blend location."""
    configured = bpy.path.abspath(prefs.godot_project) if prefs.godot_project else ""
    if configured and os.path.isdir(configured):
        return os.path.normpath(configured)
    return find_project_root(bpy.data.filepath)


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
