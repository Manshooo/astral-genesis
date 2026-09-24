"""Copy the image files a material uses into the Godot project.

Only relevant when Godot owns the materials: the .glb then carries no images at
all, and the textures have to reach the project some other way.  Copying is
content-checked so re-exporting an unchanged asset touches nothing, which is
what keeps Godot from reimporting textures on every save.

What is NOT copied matters just as much.  A layer-based painting add-on bakes
every channel it knows -- AO, roughness, metallic, displacement -- because those
are the *inputs* its packed ORM target composes from.  They are intermediates,
not maps the game loads, and shipping them doubles the texture weight of an
asset and puts it in LFS forever.  So an image whose suffix positively
identifies it as an intermediate is left in the .blend; an image whose suffix is
not recognised at all is copied, because guessing wrong in that direction loses
art.  Both cases are reported by name -- nothing here happens silently.
"""

import hashlib
import os
import shutil
from collections import namedtuple

import bpy

from . import paths, ucupaint

# copied/skipped: counts.  dropped: intermediates left behind, by name.
# unknown: copied but unrecognised, so the artist can check the naming.
CopyReport = namedtuple("CopyReport", "copied skipped dropped unknown problems")


def classify(name: str) -> str:
    """'ship', 'intermediate' or 'unknown' for one texture file name."""
    stem = os.path.splitext(os.path.basename(name))[0]
    _, suffix = ucupaint.split_channel(stem)
    if not suffix:
        return "unknown"
    return "ship" if suffix in ucupaint.CANONICAL else "intermediate"


def _digest(path: str) -> str:
    h = hashlib.md5()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def images_of(materials):
    """Every image datablock referenced by the given materials' node trees."""
    images = []
    seen = set()
    for mat in materials:
        if not mat.use_nodes or mat.node_tree is None:
            continue
        for node in mat.node_tree.nodes:
            image = getattr(node, "image", None)
            if image is not None and image.name not in seen:
                seen.add(image.name)
                images.append(image)
    return images


def copy_material_textures(root: str, texture_dir: str, materials) -> CopyReport:
    """Copy the maps these materials need into <root>/<texture_dir>."""
    rel_dir = paths.clean_rel_dir(texture_dir)
    dest_dir = os.path.join(root, rel_dir.replace("/", os.sep))
    paths.ensure_dir(dest_dir)

    copied = 0
    skipped = 0
    dropped = []
    unknown = []
    problems = []

    for image in images_of(materials):
        try:
            source = bpy.path.abspath(image.filepath_raw or image.filepath)
        except Exception:
            source = ""

        name = os.path.basename(source) or (image.name + ".png")

        kind = classify(name)
        if kind == "intermediate":
            dropped.append(name)
            continue
        if kind == "unknown":
            unknown.append(name)

        dest = os.path.join(dest_dir, name)

        if image.packed_file is not None or not source or not os.path.isfile(source):
            # Packed or generated: ask Blender to write it out, but never
            # clobber a file that is already there.
            if os.path.isfile(dest):
                skipped += 1
                continue
            try:
                image.save(filepath=dest)
                copied += 1
            except Exception as error:
                problems.append("could not write %s: %s" % (name, error))
            continue

        if os.path.isfile(dest):
            try:
                if _digest(source) == _digest(dest):
                    skipped += 1
                    continue
            except OSError as error:
                problems.append("could not compare %s: %s" % (name, error))
                continue
            problems.append("overwrote %s (content differs)" % name)

        try:
            shutil.copy2(source, dest)
            copied += 1
        except OSError as error:
            problems.append("could not copy %s: %s" % (name, error))

    return CopyReport(copied, skipped, dropped, unknown, problems)
