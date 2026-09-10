"""Pre-flight checks.

Most Blender-to-Godot pain is not an export bug, it is data that was always
going to import badly: a node named "Wall.001" (Godot strips the dot), a
material duplicated into "Stone.001" so its external .tres link breaks, a mesh
with a material but no UV map.  Catching those before the export is cheaper
than debugging them in the engine.
"""

import os

import bpy

from . import exporter, paths
from .naming import INVALID_NODE_CHARS, has_manual_suffix, object_export_name

ERROR = 'ERROR'
WARNING = 'WARNING'
INFO = 'INFO'


class Issue:
    __slots__ = ("level", "asset", "message")

    def __init__(self, level, asset, message):
        self.level = level
        self.asset = asset
        self.message = message


def validate(context, prefs, collections):
    from .prefs import get_profile

    issues = []
    root = paths.project_root(prefs)
    if not paths.is_valid_project(root):
        issues.append(Issue(ERROR, "", "Godot project root not set (no project.godot found)"))
        return issues

    if not bpy.data.filepath:
        issues.append(Issue(WARNING, "", "This .blend has never been saved, relative paths may be wrong"))

    if not collections:
        issues.append(Issue(WARNING, "", "No collection is marked 'Export as Godot Asset'"))

    destinations = {}

    for collection in collections:
        name = collection.name
        profile = get_profile(prefs, collection.godot.profile)
        if profile is None:
            issues.append(Issue(ERROR, name, "no export profile defined"))
            continue
        if collection.godot.profile and profile.name != collection.godot.profile:
            issues.append(Issue(WARNING, name,
                                "profile %r not found, falling back to %r"
                                % (collection.godot.profile, profile.name)))

        abs_file, res_file, _ = exporter.asset_paths(root, profile, collection)
        if res_file in destinations:
            issues.append(Issue(ERROR, name,
                                "writes to the same file as %r: %s" % (destinations[res_file], res_file)))
        destinations[res_file] = name

        objects = exporter.objects_of(collection, collection.godot.include_children)
        if not objects:
            issues.append(Issue(WARNING, name, "collection is empty"))
            continue

        _check_names(issues, name, objects)
        _check_meshes(issues, name, objects)
        _check_armatures(issues, name, objects, profile)
        _check_materials(issues, name, objects, profile)
        _check_physics(issues, name, objects, profile)

    return issues


def _check_ragdoll_bone(issues, asset, obj, settings, profile):
    """A PhysicalBone3D is only buildable if the bone it names survives export."""
    from . import physics

    bone = physics.bone_of(obj)
    if not bone:
        issues.append(Issue(ERROR, asset,
                            "%r is a PhysicalBone3D but names no bone: parent it to a bone or "
                            "fill the Bone field" % obj.name))
        return

    armature = physics.armature_of(obj)
    if armature is None:
        issues.append(Issue(ERROR, asset,
                            "%r wants bone %r but is not rigged or parented to any armature, so "
                            "the .glb will carry no skeleton" % (obj.name, bone)))
        return

    data_bone = armature.data.bones.get(bone)
    if data_bone is None:
        issues.append(Issue(ERROR, asset,
                            "armature %r has no bone %r (wanted by %r)"
                            % (armature.name, bone, obj.name)))
        return

    # The quiet one: with Export Deformation Bones Only a control bone never
    # reaches the .glb, so the ragdoll bone would name something Godot's
    # skeleton does not have — and the only symptom is a body that never appears.
    if profile.deform_bones_only and not data_bone.use_deform:
        issues.append(Issue(ERROR, asset,
                            "bone %r is not a deform bone and the profile exports deform bones "
                            "only, so it will not exist in Godot (wanted by %r)"
                            % (bone, obj.name)))

    if settings.joint_type == 'NONE':
        issues.append(Issue(INFO, asset,
                            "%r has no joint, so bone %r simulates free of the rest of the "
                            "ragdoll" % (obj.name, bone)))


def _check_physics(issues, asset, objects, profile):
    """Collision metadata is inert unless it is exported and read back."""
    from . import physics
    from .naming import find_godot_suffix

    tagged = [obj for obj in objects if physics.has_physics(obj)]
    if not tagged:
        return

    if not profile.export_extras:
        issues.append(Issue(ERROR, asset,
                            "%d object(s) carry collision metadata but the profile has Custom "
                            "Properties off, so it would be dropped on export" % len(tagged)))
    if not profile.import_script:
        issues.append(Issue(WARNING, asset,
                            "collision metadata is exported but the profile has no import "
                            "script, so Godot will not build any physics nodes. Use "
                            "Collisions > Godot Side > Install Godot Import Script"))

    for obj in tagged:
        settings = obj.godot_physics

        if settings.shape in physics.STATIC_ONLY_SHAPES and settings.body in physics.MOVING_BODIES:
            issues.append(Issue(ERROR, asset,
                                "%r uses Trimesh on a %s; ConcavePolygonShape3D only works on a "
                                "static body" % (obj.name, physics.BODY_NODE[settings.body])))

        if settings.body == 'PHYSICAL_BONE':
            _check_ragdoll_bone(issues, asset, obj, settings, profile)

        if settings.body != 'NONE':
            scale = obj.scale
            if max(scale) - min(scale) > 1e-4:
                issues.append(Issue(WARNING, asset,
                                    "%r becomes a %s but has non-uniform scale %.3f, %.3f, %.3f, "
                                    "which Godot warns about on collision nodes"
                                    % (obj.name, physics.BODY_NODE[settings.body],
                                       scale.x, scale.y, scale.z)))

        if settings.body != 'NONE' and obj.godot.collision != 'NONE':
            issues.append(Issue(WARNING, asset,
                                "%r has both a name-suffix hint (%s) and collision metadata; "
                                "Godot would build collision twice"
                                % (obj.name, obj.godot.collision)))

        if settings.shape != 'NONE' and settings.body == 'NONE':
            ancestor = obj.parent
            while ancestor is not None and ancestor.godot_physics.body == 'NONE':
                ancestor = ancestor.parent
            if ancestor is None:
                issues.append(Issue(WARNING, asset,
                                    "%r is a collision shape with no body above it; the import "
                                    "script will add a StaticBody3D for it" % obj.name))

        suffix = find_godot_suffix(obj.name)
        if suffix:
            issues.append(Issue(WARNING, asset,
                                "%r ends in a Godot suffix (-%s), so the stock importer would "
                                "also act on it" % (obj.name, suffix)))

        # A sphere, capsule or cylinder cannot survive non-uniform scale: Godot
        # picks a single radius, so the shape stops matching what Blender draws.
        if settings.shape in ('SPHERE', 'CAPSULE', 'CYLINDER'):
            world = obj.matrix_world.to_scale()
            if max(world) - min(world) > 1e-4:
                issues.append(Issue(WARNING, asset,
                                    "%r is a round shape under non-uniform scale %.3f, %.3f, "
                                    "%.3f; Godot will pick one radius. Apply scale or use Box"
                                    % (obj.name, world.x, world.y, world.z)))

        if settings.shape == 'CONCAVE' and obj.type == 'MESH' and len(obj.data.polygons) > 5000:
            issues.append(Issue(INFO, asset,
                                "%r builds a Trimesh from %d faces; consider a primitive"
                                % (obj.name, len(obj.data.polygons))))


def _check_names(issues, asset, objects):
    exported = {}
    for obj in objects:
        bad = [c for c in obj.name if c in INVALID_NODE_CHARS]
        if bad:
            issues.append(Issue(WARNING, asset,
                                "%r contains %s which Godot strips from node names"
                                % (obj.name, " ".join(sorted(set(bad))))))
        manual = has_manual_suffix(obj.name)
        if manual and obj.godot.collision != 'NONE':
            issues.append(Issue(ERROR, asset,
                                "%r already ends in %s and also has a Godot Node hint set; "
                                "the two would stack" % (obj.name, manual)))

        final = object_export_name(obj, obj.godot)
        if final in exported:
            issues.append(Issue(ERROR, asset,
                                "%r and %r both export as node %r"
                                % (exported[final], obj.name, final)))
        exported[final] = obj.name


def _check_meshes(issues, asset, objects):
    for obj in objects:
        if obj.type != 'MESH':
            continue
        mesh = obj.data
        if obj.godot.collision in ('COLONLY', 'CONVCOLONLY', 'NAVMESH', 'OCCONLY'):
            continue  # visual data is discarded anyway
        if mesh.materials and not mesh.uv_layers:
            issues.append(Issue(WARNING, asset,
                                "%r has materials but no UV map" % obj.name))
        if len(mesh.uv_layers) > 2:
            issues.append(Issue(INFO, asset,
                                "%r has %d UV maps, Godot uses at most 2 (UV and UV2)"
                                % (obj.name, len(mesh.uv_layers))))
        scale = obj.scale
        if scale.x * scale.y * scale.z < 0.0:
            issues.append(Issue(WARNING, asset,
                                "%r has negative scale, normals will be inverted in Godot"
                                % obj.name))
        empty_slots = [i for i, slot in enumerate(obj.material_slots) if slot.material is None]
        if empty_slots:
            issues.append(Issue(WARNING, asset,
                                "%r has empty material slot(s) %s"
                                % (obj.name, empty_slots)))


def _check_armatures(issues, asset, objects, profile):
    armatures = [obj for obj in objects if obj.type == 'ARMATURE']
    if len(armatures) > 1:
        issues.append(Issue(WARNING, asset,
                            "%d armatures in one asset (%s). Godot creates one Skeleton3D per "
                            "armature; consider one asset per character"
                            % (len(armatures), ", ".join(a.name for a in armatures))))
    for arm in armatures:
        if any(abs(value - 1.0) > 1e-4 for value in arm.scale):
            issues.append(Issue(WARNING, asset,
                                "armature %r has unapplied scale %.3f, %.3f, %.3f"
                                % (arm.name, arm.scale.x, arm.scale.y, arm.scale.z)))
    if profile.export_animations and not armatures:
        has_anim = any(obj.animation_data and obj.animation_data.action for obj in objects)
        if not has_anim:
            issues.append(Issue(INFO, asset,
                                "profile exports animations but the asset has none"))
    if profile.apply_modifiers:
        for obj in objects:
            if obj.type == 'MESH' and obj.data.shape_keys:
                issues.append(Issue(ERROR, asset,
                                    "%r has shape keys but the profile applies modifiers, "
                                    "which drops them" % obj.name))


def _check_materials(issues, asset, objects, profile):
    materials = exporter.materials_of(objects)
    for mat in materials:
        base, _, tail = mat.name.rpartition(".")
        if base and tail.isdigit() and len(tail) == 3:
            issues.append(Issue(WARNING, asset,
                                "material %r looks like an accidental duplicate of %r; "
                                "external material links are keyed by name"
                                % (mat.name, base)))
    if profile.material_policy == 'EXTRACT' and not profile.subfolder_per_asset:
        issues.append(Issue(WARNING, asset,
                            "profile extracts textures but does not use a folder per asset, "
                            "so images land next to every other asset in the folder"))
    if profile.material_policy == 'EXTERNAL' and not materials:
        issues.append(Issue(INFO, asset, "no materials to link"))
