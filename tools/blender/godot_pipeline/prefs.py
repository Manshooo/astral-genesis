"""Add-on preferences: the Godot project root and the library of export profiles.

Profiles live in preferences (shared by every .blend of the project) but can be
saved to and loaded from <godot project>/godot_pipeline.json, which is what
makes them reviewable and shareable through the game repo.
"""

import json
import os

import bpy
from bpy.props import BoolProperty, CollectionProperty, IntProperty, StringProperty
from bpy.types import AddonPreferences, UIList

from . import paths
from .props import GP_ExportProfile

CONFIG_FILE = "godot_pipeline.json"

# Profile presets aimed at a typical dungeon-crawler asset breakdown.  They are
# only starting points: the real value is that every asset of a kind exports
# identically, not the specific numbers.
DEFAULT_PROFILES = [
    {
        "name": "Character",
        "description": "Rigged, animated actor. One armature per asset",
        "dest_dir": "assets/characters",
        "subfolder_per_asset": True,
        "material_policy": 'EXTERNAL',
        "apply_modifiers": False,          # keep shape keys exportable
        "export_animations": True,
        "animation_mode": 'ACTIONS',
        "deform_bones_only": True,
        "rest_position_armature": True,
        "root_type": 'NONE',
        "generate_lods": False,            # skinned meshes rarely benefit
        "create_shadow_meshes": False,
        "light_bake_mode": 'DYNAMIC',
        "import_animations": True,
    },
    {
        "name": "Level Chunk",
        "description": "Room or corridor piece, collision authored with -col suffixes",
        "dest_dir": "assets/levels",
        "subfolder_per_asset": True,
        "material_policy": 'EXTERNAL',
        "apply_modifiers": True,
        "export_animations": False,
        "root_type": 'NONE',
        "generate_lods": True,
        "create_shadow_meshes": True,
        "light_bake_mode": 'STATIC',
        "import_animations": False,
    },
    {
        "name": "Prop",
        "description": "Static furniture and set dressing",
        "dest_dir": "assets/props",
        "subfolder_per_asset": True,
        "material_policy": 'EXTERNAL',
        "apply_modifiers": True,
        "export_animations": False,
        "root_type": 'NONE',
        "generate_lods": True,
        "create_shadow_meshes": True,
        "light_bake_mode": 'DYNAMIC',
        "import_animations": False,
    },
    {
        "name": "Interactive",
        "description": "Prop with gameplay behaviour. Custom properties ride along as node metadata",
        "dest_dir": "assets/props/interactive",
        "subfolder_per_asset": True,
        "material_policy": 'EXTERNAL',
        "apply_modifiers": True,
        "export_extras": True,
        "export_animations": True,
        "animation_mode": 'ACTIONS',
        "root_type": 'STATIC',
        "generate_lods": False,
        "create_shadow_meshes": True,
        "light_bake_mode": 'DYNAMIC',
        "import_animations": True,
    },
]

# Only these are round-tripped to JSON. Keeping an explicit list means adding a
# property later cannot silently corrupt an existing config file.
_SKIP_KEYS = {"rna_type"}


def profile_to_dict(profile) -> dict:
    data = {}
    for key in profile.bl_rna.properties.keys():
        if key in _SKIP_KEYS:
            continue
        value = getattr(profile, key)
        if isinstance(value, (bool, int, float, str)):
            data[key] = value
    return data


def dict_to_profile(profile, data: dict):
    valid = set(profile.bl_rna.properties.keys())
    for key, value in data.items():
        if key in valid and key not in _SKIP_KEYS:
            try:
                setattr(profile, key, value)
            except (TypeError, ValueError):
                pass


class GP_UL_profiles(UIList):
    def draw_item(self, context, layout, data, item, icon, active_data, active_prop, index):
        row = layout.row(align=True)
        row.prop(item, "name", text="", emboss=False, icon='PRESET')
        row.label(text=item.dest_dir, icon='FILE_FOLDER')


class GodotPipelinePrefs(AddonPreferences):
    bl_idname = __package__

    godot_project: StringProperty(
        name="Godot Project",
        description="Folder containing project.godot. Leave empty to search upwards from the "
                    ".blend file location",
        subtype='DIR_PATH',
        default="",
    )
    profiles: CollectionProperty(type=GP_ExportProfile)
    active_profile: IntProperty(default=0)

    verbose: BoolProperty(
        name="Verbose Log",
        description="Print every exported file and every .import key that was changed",
        default=True,
    )
    dry_run: BoolProperty(
        name="Dry Run",
        description="Report what would be exported without writing any file",
        default=False,
    )

    def draw(self, context):
        layout = self.layout

        box = layout.box()
        box.prop(self, "godot_project")
        root = paths.project_root(self)
        if paths.is_valid_project(root):
            box.label(text=root, icon='CHECKMARK')
        elif root:
            box.label(text="No project.godot in " + root, icon='ERROR')
        else:
            box.label(text="Godot project not found. Set it above.", icon='ERROR')

        row = layout.row()
        row.prop(self, "verbose")
        row.prop(self, "dry_run")

        layout.separator()
        layout.label(text="Export Profiles")

        row = layout.row()
        row.template_list("GP_UL_profiles", "", self, "profiles", self, "active_profile", rows=4)
        col = row.column(align=True)
        col.operator("godot_pipeline.profile_add", icon='ADD', text="")
        col.operator("godot_pipeline.profile_remove", icon='REMOVE', text="")
        col.separator()
        col.operator("godot_pipeline.profile_reset", icon='LOOP_BACK', text="")

        row = layout.row(align=True)
        row.operator("godot_pipeline.config_load", icon='IMPORT')
        row.operator("godot_pipeline.config_save", icon='EXPORT')

        if 0 <= self.active_profile < len(self.profiles):
            draw_profile(layout, self.profiles[self.active_profile])


def draw_profile(layout, profile):
    layout.separator()
    box = layout.box()
    box.prop(profile, "description")

    col = box.column(align=True)
    col.label(text="Destination", icon='FILE_FOLDER')
    col.prop(profile, "dest_dir")
    col.prop(profile, "subfolder_per_asset")

    col = box.column(align=True)
    col.label(text="glTF Content", icon='EXPORT')
    col.prop(profile, "file_format")
    col.prop(profile, "material_policy")
    row = col.row(align=True)
    row.prop(profile, "apply_modifiers", toggle=True)
    row.prop(profile, "export_tangents", toggle=True)
    row = col.row(align=True)
    row.prop(profile, "export_extras", toggle=True)
    row.prop(profile, "export_vertex_colors", toggle=True)
    row = col.row(align=True)
    row.prop(profile, "export_attributes", toggle=True)
    row.prop(profile, "use_gpu_instances", toggle=True)
    row = col.row(align=True)
    row.prop(profile, "export_cameras", toggle=True)
    row.prop(profile, "export_lights", toggle=True)
    col.prop(profile, "yup")

    col = box.column(align=True)
    col.label(text="Animation", icon='ARMATURE_DATA')
    col.prop(profile, "export_animations")
    sub = col.column(align=True)
    sub.active = profile.export_animations
    sub.prop(profile, "animation_mode")
    sub.prop(profile, "deform_bones_only")
    sub.prop(profile, "rest_position_armature")
    sub.prop(profile, "influences")
    sub.prop(profile, "optimize_animation")

    col = box.column(align=True)
    col.label(text="Materials and Textures", icon='MATERIAL')
    col.prop(profile, "material_dir")
    col.prop(profile, "generate_material_stubs")
    col.prop(profile, "link_external_materials")
    col.prop(profile, "copy_textures")
    sub = col.column(align=True)
    sub.active = profile.copy_textures
    sub.prop(profile, "texture_dir")

    col = box.column(align=True)
    col.label(text="Godot Import Settings", icon='IMPORT')
    col.prop(profile, "write_import_file")
    sub = col.column(align=True)
    sub.active = profile.write_import_file
    sub.prop(profile, "create_import_file")
    sub.prop(profile, "root_type")
    sub.prop(profile, "root_scale")
    row = sub.row(align=True)
    row.prop(profile, "ensure_tangents", toggle=True)
    row.prop(profile, "generate_lods", toggle=True)
    row = sub.row(align=True)
    row.prop(profile, "create_shadow_meshes", toggle=True)
    row.prop(profile, "import_animations", toggle=True)
    sub.prop(profile, "light_bake_mode")
    sub.prop(profile, "animation_fps")
    sub.prop(profile, "import_script")

    col = box.column(align=True)
    col.label(text="Tile Kit", icon='MESH_GRID')
    col.prop(profile, "cell_size")
    col.prop(profile, "cell_height")


def get_prefs(context=None) -> GodotPipelinePrefs:
    context = context or bpy.context
    return context.preferences.addons[__package__].preferences


def get_profile(prefs, name: str):
    """Profile by name, falling back to the first one so a typo never blocks an export."""
    if name:
        for profile in prefs.profiles:
            if profile.name == name:
                return profile
    return prefs.profiles[0] if len(prefs.profiles) else None


def reset_profiles(prefs):
    prefs.profiles.clear()
    for preset in DEFAULT_PROFILES:
        profile = prefs.profiles.add()
        dict_to_profile(profile, preset)
    prefs.active_profile = 0


def config_path(prefs) -> str:
    root = paths.project_root(prefs)
    return os.path.join(root, CONFIG_FILE) if root else ""


def save_config(prefs) -> str:
    path = config_path(prefs)
    if not path:
        raise RuntimeError("Godot project root is not set")
    data = {
        "version": 1,
        "profiles": [profile_to_dict(p) for p in prefs.profiles],
    }
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    return path


def load_config(prefs) -> str:
    path = config_path(prefs)
    if not path or not os.path.isfile(path):
        raise RuntimeError("No %s next to project.godot" % CONFIG_FILE)
    with open(path, "r", encoding="utf-8") as handle:
        data = json.load(handle)
    prefs.profiles.clear()
    for entry in data.get("profiles", []):
        dict_to_profile(prefs.profiles.add(), entry)
    prefs.active_profile = 0
    return path


CLASSES = (GP_UL_profiles, GodotPipelinePrefs)


def register():
    for cls in CLASSES:
        bpy.utils.register_class(cls)
    # First run: give the user something to click instead of an empty list.
    try:
        prefs = bpy.context.preferences.addons[__package__].preferences
    except (KeyError, AttributeError):
        return
    if prefs is not None and not len(prefs.profiles):
        reset_profiles(prefs)


def unregister():
    for cls in reversed(CLASSES):
        bpy.utils.unregister_class(cls)
