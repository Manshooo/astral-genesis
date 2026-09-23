"""The export core: collect marked collections, ship each one as an independent asset."""

import os
import time
from contextlib import contextmanager

import bpy

from . import godot_import, naming, paths, textures
from .naming import material_export_name, object_export_name, sanitize_file_name


class AssetResult:
    __slots__ = ("collection", "status", "path", "messages", "seconds")

    def __init__(self, collection):
        self.collection = collection
        self.status = "pending"
        self.path = ""
        self.messages = []
        self.seconds = 0.0

    def note(self, text):
        self.messages.append(text)


# -- asset discovery --------------------------------------------------------

def iter_scene_collections(scene):
    """Every collection reachable from the scene, depth first, each yielded once."""
    seen = set()

    def walk(collection):
        for child in collection.children:
            if child.name in seen:
                continue
            seen.add(child.name)
            yield child
            yield from walk(child)

    yield from walk(scene.collection)


def collect_assets(scene, selected_only=False):
    assets = []
    for collection in iter_scene_collections(scene):
        settings = collection.godot
        if not settings.is_asset or settings.skip:
            continue
        if selected_only and not _is_selected(collection):
            continue
        assets.append(collection)
    return assets


def _is_selected(collection):
    active = bpy.context.view_layer.active_layer_collection
    return active is not None and active.collection == collection


def objects_of(collection, recursive=True):
    return list(collection.all_objects) if recursive else list(collection.objects)


def materials_of(objects):
    materials = []
    seen = set()
    for obj in objects:
        for slot in getattr(obj, "material_slots", []):
            mat = slot.material
            if mat is not None and mat.name not in seen:
                seen.add(mat.name)
                materials.append(mat)
    return materials


def actions_of(objects):
    actions = []
    seen = set()
    for obj in objects:
        anim = obj.animation_data
        for candidate in ([anim.action] if anim and anim.action else []) + \
                         ([strip.action for track in (anim.nla_tracks if anim else [])
                           for strip in track.strips if strip.action]):
            if candidate is not None and candidate.name not in seen:
                seen.add(candidate.name)
                actions.append(candidate)
    return actions


# -- destination ------------------------------------------------------------

def asset_rel_dir(profile, collection) -> str:
    """The asset's own folder, relative to the Godot project root."""
    settings = collection.godot
    rel_dir = paths.clean_rel_dir(settings.dest_dir or profile.dest_dir)
    if profile.subfolder_per_asset:
        name = sanitize_file_name(settings.file_name or collection.name)
        rel_dir = "%s/%s" % (rel_dir, name) if rel_dir else name
    return rel_dir


def asset_paths(root: str, profile, collection):
    """Return (abs_file, res_file, abs_dir) for one asset."""
    settings = collection.godot
    rel_dir = asset_rel_dir(profile, collection)
    name = sanitize_file_name(settings.file_name or collection.name)
    ext = ".glb" if profile.file_format == 'GLB' else ".gltf"
    abs_dir = os.path.join(root, rel_dir.replace("/", os.sep))
    abs_file = os.path.join(abs_dir, name + ext)
    res_file = "res://%s/%s%s" % (rel_dir, name, ext) if rel_dir else "res://%s%s" % (name, ext)
    return abs_file, res_file, abs_dir


def _under(base: str, leaf: str) -> str:
    return "%s/%s" % (base, leaf) if base else leaf


def material_dirs(profile, collection, material):
    """(materials folder, textures folder) that own this material, project-relative.

    A material marked as living beside its asset takes its textures with it, so
    the two folders always move together — that is the whole point of the
    setting, and splitting them would put a unique texture in the shared pile.
    """
    shared = paths.clean_rel_dir(profile.material_dir)
    if material.godot.location == 'ASSET' or not shared:
        base = asset_rel_dir(profile, collection)
        return _under(base, "materials"), _under(base, "textures")
    return shared, paths.clean_rel_dir(profile.texture_dir)


def material_res_path(root: str, profile, collection, material) -> str:
    """Where the external .tres for `material` lives."""
    if material.godot.godot_path:
        return material.godot.godot_path
    rel_dir, _ = material_dirs(profile, collection, material)
    return "res://%s/%s.tres" % (rel_dir, sanitize_file_name(material.name))


# -- temporary scene state --------------------------------------------------

def _find_layer_collection(layer_collection, collection):
    if layer_collection.collection == collection:
        return layer_collection
    for child in layer_collection.children:
        found = _find_layer_collection(child, collection)
        if found is not None:
            return found
    return None


@contextmanager
def visible_for_export(view_layer, collection, objects):
    """Make sure the exporter can actually see the asset.

    Objects in an excluded layer collection or with hide_viewport set are not
    evaluated by the dependency graph, so they would silently export empty.
    """
    restore = []
    layer = _find_layer_collection(view_layer.layer_collection, collection)
    if layer is not None:
        if layer.exclude:
            restore.append((layer, "exclude", True))
            layer.exclude = False
        if layer.hide_viewport:
            restore.append((layer, "hide_viewport", True))
            layer.hide_viewport = False
    if collection.hide_viewport:
        restore.append((collection, "hide_viewport", True))
        collection.hide_viewport = False
    for obj in objects:
        if obj.hide_viewport:
            restore.append((obj, "hide_viewport", True))
            obj.hide_viewport = False
    try:
        yield
    finally:
        for target, attr, value in reversed(restore):
            try:
                setattr(target, attr, value)
            except ReferenceError:
                pass


def suffix_renames(objects, materials, actions):
    """(datablock, new_name) pairs implementing the Godot import hints."""
    pairs = []
    for obj in objects:
        pairs.append((obj, object_export_name(obj, obj.godot)))
    for mat in materials:
        pairs.append((mat, material_export_name(mat, mat.godot)))
    for action in actions:
        if getattr(action, "godot_loop", False) and not action.name.lower().endswith("-loop"):
            pairs.append((action, action.name + naming.ANIM_SUFFIXES['loop']))
    return pairs


# -- glTF operator ----------------------------------------------------------

def _supported_kwargs(kwargs: dict) -> dict:
    """Drop settings this Blender build's exporter does not know about.

    The glTF operator gains and renames properties between releases; filtering
    keeps one add-on working across 4.2 through 5.x instead of crashing on an
    unknown keyword.
    """
    try:
        known = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
    except Exception:
        return kwargs
    return {key: value for key, value in kwargs.items() if key in known}


def build_gltf_kwargs(profile, collection, filepath: str) -> dict:
    external_materials = profile.material_policy == 'EXTERNAL'
    kwargs = {
        "filepath": filepath,
        "check_existing": False,
        "export_format": profile.file_format,

        # Scope: exactly this collection, nothing else in the .blend.
        "use_selection": False,
        "use_visible": False,
        "use_renderable": False,
        "use_active_scene": False,
        "use_active_collection": False,
        "collection": collection.name,
        "at_collection_center": bool(collection.godot.at_center),

        # Geometry
        "export_apply": bool(profile.apply_modifiers),
        "export_yup": bool(profile.yup),
        "export_texcoords": True,
        "export_normals": True,
        "export_tangents": bool(profile.export_tangents),
        "export_attributes": bool(profile.export_attributes),
        "export_extras": bool(profile.export_extras),
        "export_gpu_instances": bool(profile.use_gpu_instances),
        "export_cameras": bool(profile.export_cameras),
        "export_lights": bool(profile.export_lights),
        "export_vertex_color": 'MATERIAL' if profile.export_vertex_colors else 'NONE',
        "export_all_vertex_colors": False,

        # Materials: names and slots always travel, images only when Godot is
        # not the owner of the material.
        "export_materials": 'EXPORT',
        "export_image_format": 'NONE' if external_materials else 'AUTO',
        "export_keep_originals": False,
        "export_unused_images": False,
        "export_unused_textures": False,

        # Skinning
        "export_skins": True,
        "export_influence_nb": int(profile.influences),
        "export_all_influences": False,
        "export_def_bones": bool(profile.deform_bones_only),
        "export_rest_position_armature": bool(profile.rest_position_armature),
        "export_leaf_bone": False,

        # Animation
        "export_animations": bool(profile.export_animations),
        "export_animation_mode": profile.animation_mode,
        "export_optimize_animation_size": bool(profile.optimize_animation),
        "export_morph": True,
    }
    if profile.file_format == 'GLTF_SEPARATE' and not external_materials:
        kwargs["export_texture_dir"] = "textures"
    return _supported_kwargs(kwargs)


# -- one asset --------------------------------------------------------------

def export_asset(context, prefs, collection, root: str, profile) -> AssetResult:
    result = AssetResult(collection)
    started = time.time()

    abs_file, res_file, abs_dir = asset_paths(root, profile, collection)
    result.path = res_file

    objects = objects_of(collection, collection.godot.include_children)
    if not objects:
        result.status = "skipped"
        result.note("collection is empty")
        return result

    materials = materials_of(objects)
    actions = actions_of(objects) if profile.export_animations else []

    if prefs.dry_run:
        result.status = "dry-run"
        result.note("%d objects, %d materials" % (len(objects), len(materials)))
        return result

    paths.ensure_dir(abs_dir)

    renames = suffix_renames(objects, materials, actions)
    with visible_for_export(context.view_layer, collection, objects):
        with naming.renamed(renames) as collisions:
            for wanted, got in collisions:
                result.note("name collision: wanted %r, Blender assigned %r" % (wanted, got))
            kwargs = build_gltf_kwargs(profile, collection, abs_file)
            try:
                bpy.ops.export_scene.gltf(**kwargs)
            except RuntimeError as error:
                result.status = "failed"
                result.note(str(error))
                result.seconds = time.time() - started
                return result

    # -- textures ------------------------------------------------------------
    if profile.copy_textures:
        # Grouped by destination: materials that live beside the asset put their
        # textures there too, shared ones go to the common folder.
        groups = {}
        for mat in materials:
            groups.setdefault(material_dirs(profile, collection, mat)[1], []).append(mat)
        for tex_dir, group in sorted(groups.items()):
            report = textures.copy_material_textures(root, tex_dir, group)
            if report.copied:
                result.note("copied %d texture(s) to %s" % (report.copied, tex_dir))
            if report.skipped:
                result.note("%d texture(s) already up to date in %s" % (report.skipped, tex_dir))
            if report.dropped:
                result.note("intermediate map(s) kept out of the project: %s"
                            % ", ".join(report.dropped))
            for name in report.unknown:
                result.note("%s: map suffix not recognised, copied as is" % name)
            for problem in report.problems:
                result.note(problem)

    # -- external materials --------------------------------------------------
    material_links = {}
    if profile.material_policy == 'EXTERNAL' and profile.link_external_materials:
        for mat in materials:
            res_path = material_res_path(root, profile, collection, mat)
            # The key must match the material name as it appears in the glTF,
            # suffixes included.
            material_links[material_export_name(mat, mat.godot)] = res_path
            if profile.generate_material_stubs:
                abs_path = paths.res_to_abs(root, res_path)
                if godot_import.ensure_material_stub(abs_path, mat.name):
                    result.note("created material stub %s" % res_path)

    # -- .import -------------------------------------------------------------
    if profile.write_import_file:
        status, changed, warning = godot_import.write_import_settings(
            abs_file, res_file, profile, profile.material_policy,
            material_links, profile.create_import_file)
        if warning:
            result.note(warning)
        if status in ("created", "patched"):
            result.note("%s .import (%s)" % (status, ", ".join(changed) if changed else "materials"))

    result.status = "ok"
    result.seconds = time.time() - started
    return result


# -- batch ------------------------------------------------------------------

def export_many(context, prefs, collections):
    """Export a list of collections. Returns (results, fatal_error)."""
    root = paths.project_root(prefs)
    if not paths.is_valid_project(root):
        return [], "Godot project root not set (no project.godot found)"

    from .prefs import get_profile

    results = []
    for collection in collections:
        profile = get_profile(prefs, collection.godot.profile)
        if profile is None:
            result = AssetResult(collection)
            result.status = "failed"
            result.note("no export profile defined")
            results.append(result)
            continue
        results.append(export_asset(context, prefs, collection, root, profile))
    return results, ""


def format_report(results) -> str:
    ok = sum(1 for r in results if r.status == "ok")
    failed = sum(1 for r in results if r.status == "failed")
    skipped = sum(1 for r in results if r.status in ("skipped", "dry-run"))
    return "Godot Pipeline: %d exported, %d skipped, %d failed" % (ok, skipped, failed)
