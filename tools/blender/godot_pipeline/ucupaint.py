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
import re

import bpy

# Channel token as Ucupaint writes it -> our suffix.  Order matters: the longest
# token has to win, or «Ambient Occlusion» is read as «Occlusion»… and worse,
# «Base Color» as «Color» would be right by luck while «Color Mask» would not.
CHANNEL_MAP = [
    # Канал Ucupaint 3.0. Без своей строки «Vector Displacement» читался бы по
    # хвосту как «displacement», то есть как карта высот, а это другая карта.
    ("vector displacement", "vdm"),
    ("vdm", "vdm"),
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

# Хвост дубликата: «.001» дописывает Blender, « 1» — Ucupaint. Конвертация файла
# в Ucupaint 3.0 переименовывает каждую запечённую картинку в уникальное имя и
# сталкивается с ней же самой: «T_door_albedo» становится «T_door_albedo 1».
DUPLICATE_TAIL = re.compile(r"(?: \d+|\.\d{3})$")


def _strip_separators(text: str) -> str:
    return text.strip(SEPARATORS)


def split_channel(name: str):
    """(base, suffix) for an image name, or (name, "") when nothing matched."""
    name = DUPLICATE_TAIL.sub("", name)
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
    # Ucupaint называет запечённое по дереву слоёв, а дерево по умолчанию зовётся
    # «Ucupaint MAT_x» (или переименовано в «UCU_MAT_x»). Всё до токена MAT_ —
    # имя дерева, а не ассета: без этого вышло T_Ucupaint_MAT_architect_artifact.
    # Токен ищется как отдельное слово, и заодно лечится уже испорченное имя.
    found = re.search(r"(?:^|[ _\-.])(?:MAT|mat)_", text)
    if found:
        text = text[found.end():]
    else:
        for prefix in ("T_", "t_"):
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


# -- цели запечки (Ucupaint 3.0) ----------------------------------------------
#
# С 3.0 каждый канал печётся в цель запечки, и картинку цель называет своим
# именем. Цель, названная по конвенции, сразу печёт T_door_albedo, и Save All
# Baked Images пишет T_door_albedo.png: переименовывать после каждой новой
# запечки становится нечего. Поэтому ренеймер правит и цели, а не только картинки.

def _is_layer_tree(tree) -> bool:
    yp = getattr(tree, "yp", None)
    return yp is not None and getattr(yp, "is_ypaint_node", False)


def layer_trees_of_materials(materials):
    """Ucupaint layer trees used directly by these materials, in a stable order."""
    trees = []
    seen = set()
    for mat in materials:
        if not mat or not mat.use_nodes or mat.node_tree is None:
            continue
        for node in mat.node_tree.nodes:
            tree = getattr(node, "node_tree", None)
            if tree is not None and _is_layer_tree(tree) and tree.name not in seen:
                seen.add(tree.name)
                trees.append(tree)
    return trees


def all_layer_trees():
    return [tree for tree in bpy.data.node_groups if _is_layer_tree(tree)]


def _baked_image(tree, target):
    node = tree.nodes.get(target.baked_node) if target.baked_node else None
    return getattr(node, "image", None)


class TargetPlan:
    """One Ucupaint bake target and its new name."""

    def __init__(self, tree, target, new_name):
        self.tree = tree
        self.target = target
        self.old_name = target.name
        self.new_name = new_name


def plan_target_renames(trees, override: str = ""):
    """Bake targets to rename, as a list of TargetPlan.

    Only targets that matter: a channel bakes into it, or it already holds a
    baked image.  The rest are Ucupaint's own spares — «Normal without Height»
    is read as a height map by its tail, and renaming it would only add noise.
    The name comes from the baked image when there is one, so the target and
    its image end up with the same name.
    """
    plans = []
    for tree in trees:
        yp = tree.yp
        used = {channel.bake_target_name for channel in yp.channels}
        taken = {target.name for target in yp.bake_targets}
        for target in yp.bake_targets:
            if target.data_type != 'IMAGE':
                continue
            image = _baked_image(tree, target)
            if target.name not in used and image is None:
                continue
            new_name = ""
            if image is not None:
                new_name = target_name(image.name, override)
            if not new_name:
                new_name = target_name(target.name, override)
            if not new_name or new_name == target.name or new_name in taken:
                continue
            taken.add(new_name)
            plans.append(TargetPlan(tree, target, new_name))
    return plans


def apply_target_plan(plan) -> str:
    """Rename one bake target. Its own update repoints the channels using it."""
    plan.target.name = plan.new_name
    if plan.target.name != plan.new_name:
        return "имя цели не встало: %s" % plan.target.name
    return ""


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
