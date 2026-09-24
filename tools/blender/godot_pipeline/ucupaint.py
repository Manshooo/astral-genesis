"""Rename baked textures to the project's convention.

Ucupaint names what it bakes after the channel it baked: «MAT_door Color»,
«MAT_door Ambient Occlusion», and whatever the artist typed for a custom bake
target.  Godot does not care about texture file names at all — nothing in the
engine parses them — so this is purely the project's own convention, and that is
exactly why it has to be enforced somewhere: names with spaces and with the
material's own prefix are what ended up committed last time.

Target shape:  T_<base>_<map>.png,  where <map> is one of the four maps §6 of
the pipeline doc allows.  Anything else is still renamed consistently, but is
reported separately — an asset shipping a separate _roughness means the ORM pack
did not happen.
"""

import os

import bpy

# Channel token as Ucupaint writes it -> our suffix.  Order matters: the longest
# token has to win, or «Ambient Occlusion» is read as «Occlusion»… and worse,
# «Base Color» as «Color» would be right by luck while «Color Mask» would not.
CHANNEL_MAP = [
    ("ambient occlusion", "ao"),
    ("occlusion roughness metallic", "orm"),
    ("ao roughness metallic", "orm"),
    ("base color", "albedo"),
    ("basecolor", "albedo"),
    ("displacement", "height"),
    ("metalness", "metallic"),
    ("metallic", "metallic"),
    ("roughness", "roughness"),
    ("emissive", "emission"),
    ("emission", "emission"),
    ("specular", "specular"),
    ("opacity", "alpha"),
    ("normal", "n"),
    ("albedo", "albedo"),
    ("diffuse", "albedo"),
    ("color", "albedo"),
    ("height", "height"),
    ("bump", "n"),
    ("alpha", "alpha"),
    ("orm", "orm"),
    ("ao", "ao"),
    # Наш собственный суффикс нормали. Без него ренеймер не узнавал то, что сам
    # же и написал: «T_door_n» разбирался как имя без карты. Один символ здесь
    # безопасен только благодаря правилу разделителя ниже — «Stone» кончается на
    # «n», но перед ним «o», а не «_», и потому картой не считается.
    ("n", "n"),
]

# «ARM» is a real name for the same pack, but it is deliberately NOT listed: in
# a project with rigged characters «_arm» is a body part far more often than a
# texture channel, and «Shield_arm» silently becoming «T_Shield_orm» is worse
# than typing the ORM name out.

# §6 of the pipeline doc: everything else is a packing failure, not a map.
CANONICAL = {"albedo", "orm", "n", "emission"}

SEPARATORS = " _-."
PREFIX = "T_"


def _strip_separators(text: str) -> str:
    return text.strip(SEPARATORS)


def split_channel(name: str):
    """(base, suffix) for an image name, or (name, "") when nothing matched."""
    lowered = name.lower()
    best = None
    for token, suffix in CHANNEL_MAP:
        if not lowered.endswith(token):
            continue
        head = name[: len(name) - len(token)]
        # The token has to be a word of its own: «Armor» must not read as «arm».
        if head and head[-1] not in SEPARATORS:
            continue
        candidate = (_strip_separators(head), suffix)
        if best is None or len(candidate[0]) < len(best[0]):
            best = candidate
    return best if best is not None else (name, "")


def base_name(raw: str) -> str:
    """Asset part of the name: no MAT_/T_ prefix, no spaces."""
    text = _strip_separators(raw)
    for prefix in ("MAT_", "mat_", "T_", "t_"):
        if text.startswith(prefix):
            text = text[len(prefix):]
            break
    return _strip_separators(text).replace(" ", "_")


def target_name(image_name: str, override: str = "") -> str:
    """Convention name for an image, or "" when its map type is unrecognised."""
    raw_base, suffix = split_channel(image_name)
    if not suffix:
        return ""
    base = override or base_name(raw_base)
    if not base:
        return ""
    return "%s%s_%s" % (PREFIX, base, suffix)


def images_of_materials(materials):
    """Image datablocks referenced by these materials, in a stable order."""
    images = []
    seen = set()
    for mat in materials:
        if not mat or not mat.use_nodes or mat.node_tree is None:
            continue
        for node in mat.node_tree.nodes:
            image = getattr(node, "image", None)
            if image is not None and image.name not in seen:
                seen.add(image.name)
                images.append(image)
    return images


def materials_of_objects(objects):
    materials = []
    seen = set()
    for obj in objects:
        for slot in getattr(obj, "material_slots", []):
            mat = slot.material
            if mat is not None and mat.name not in seen:
                seen.add(mat.name)
                materials.append(mat)
    return materials


class Plan:
    """One image and what would happen to it."""

    def __init__(self, image, new_name, suffix):
        self.image = image
        self.new_name = new_name
        self.suffix = suffix
        self.old_path = ""
        self.new_path = ""
        self.note = ""

    @property
    def canonical(self) -> bool:
        return self.suffix in CANONICAL

    @property
    def renames_file(self) -> bool:
        return bool(self.new_path) and self.new_path != self.old_path


def _abs_path(image) -> str:
    raw = image.filepath_raw or image.filepath
    if not raw:
        return ""
    try:
        return os.path.normpath(bpy.path.abspath(raw))
    except Exception:
        return ""


def plan_renames(images, override: str = "", rename_files: bool = True):
    """Returns (plans, skipped) where skipped is a list of (name, reason)."""
    plans = []
    skipped = []
    claimed = {}

    for image in images:
        new_name = target_name(image.name, override)
        if not new_name:
            skipped.append((image.name, "тип карты не распознан"))
            continue

        suffix = new_name.rsplit("_", 1)[-1]
        plan = Plan(image, new_name, suffix)

        if image.packed_file is not None:
            plan.note = "запакована в .blend, файл не трогаем"
        elif rename_files:
            source = _abs_path(image)
            if not source:
                plan.note = "без файла на диске"
            elif not os.path.isfile(source):
                plan.note = "файл не найден: " + source
            else:
                extension = os.path.splitext(source)[1]
                target = os.path.join(os.path.dirname(source), new_name + extension)
                plan.old_path = source
                plan.new_path = os.path.normpath(target)

        if plan.new_path:
            owner = claimed.get(plan.new_path.lower())
            if owner is not None:
                skipped.append((image.name, "имя занято планом для " + owner))
                continue
            claimed[plan.new_path.lower()] = image.name

        if new_name == image.name and not plan.renames_file:
            skipped.append((image.name, "уже по конвенции"))
            continue

        plans.append(plan)

    return plans, skipped


def apply_plan(plan) -> str:
    """Apply one rename. Returns "" on success or a message on failure."""
    if plan.renames_file:
        # Never overwrite: a name clash here means two bakes fight for one file,
        # and losing one of them silently is worse than stopping.
        if os.path.exists(plan.new_path):
            return "%s уже существует" % os.path.basename(plan.new_path)
        try:
            os.replace(plan.old_path, plan.new_path)
        except OSError as error:
            return "не переименовал файл: %s" % error

        # Keep the path relative when it already was: a //-path travels with the
        # .blend, an absolute one pins the file to this machine.
        raw = plan.image.filepath_raw or plan.image.filepath
        if raw.startswith("//"):
            plan.image.filepath = bpy.path.relpath(plan.new_path)
        else:
            plan.image.filepath = plan.new_path
        plan.image.filepath_raw = plan.image.filepath

    plan.image.name = plan.new_name
    if plan.image.name != plan.new_name:
        return "Blender занял имя, получилось %s" % plan.image.name
    return ""
