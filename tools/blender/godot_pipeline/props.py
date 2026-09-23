"""Property groups: export profiles, per-collection asset config, per-object hints."""

import bpy
from bpy.props import (
    BoolProperty, EnumProperty, FloatProperty, IntProperty,
    PointerProperty, StringProperty,
)
from bpy.types import PropertyGroup

from .naming import COLLISION_ITEMS


MATERIAL_POLICY_ITEMS = [
    ('EXTERNAL', "Godot owns materials",
     "Export material slots and names but no images. Godot uses external .tres materials, "
     "so re-exporting geometry never touches your material setup. Sets "
     "gltf/embedded_image_handling = Discard All Textures", 0),
    ('EXTRACT', "Extract textures next to the .glb",
     "Textures travel inside the .glb and Godot extracts them next to the file on import. "
     "Only safe when the asset lives in its own folder. "
     "Sets gltf/embedded_image_handling = Extract Textures", 1),
    ('EMBED', "Keep textures embedded",
     "Textures stay inside the imported scene, nothing is written to disk. Costs VRAM "
     "(no compression). Sets gltf/embedded_image_handling = Embed as Uncompressed", 2),
]

# Where one material's .tres and its textures live.  The rule the project
# settled on: a material several assets share belongs to all of them, so it gets
# one common address; a material only one asset uses travels inside that asset,
# and deleting the asset takes its art with it instead of leaving orphans.
MATERIAL_LOCATION_ITEMS = [
    ('SHARED', "Shared folder",
     "The profile's material folder. For a palette material several assets use: it must have "
     "one address, and moving one asset must not move it", 0),
    ('ASSET', "Beside the asset",
     "materials/ and textures/ inside the asset's own folder. For a material unique to this "
     "asset", 1),
]

PHYSICS_ROOT_ITEMS = [
    ('NONE', "Node3D", "Plain Node3D root", 0),
    ('STATIC', "StaticBody3D", "Import the scene root as a StaticBody3D", 1),
    ('AREA', "Area3D", "Import the scene root as an Area3D", 2),
    ('RIGID', "RigidBody3D", "Import the scene root as a RigidBody3D", 3),
    ('CHAR', "CharacterBody3D", "Import the scene root as a CharacterBody3D", 4),
]

PHYSICS_ROOT_TYPE = {
    'NONE': "", 'STATIC': "StaticBody3D", 'AREA': "Area3D",
    'RIGID': "RigidBody3D", 'CHAR': "CharacterBody3D",
}

LIGHT_BAKE_ITEMS = [
    ('DISABLED', "Disabled", "No global illumination contribution", 0),
    ('DYNAMIC', "Dynamic", "Contributes to VoxelGI / SDFGI", 1),
    ('STATIC', "Static Lightmaps", "Generates UV2 and participates in lightmap baking", 2),
]

LIGHT_BAKE_VALUE = {'DISABLED': 0, 'DYNAMIC': 1, 'STATIC': 2}


class GP_ExportProfile(PropertyGroup):
    """A reusable bundle of glTF export settings plus Godot import settings.

    One profile per asset *kind* (prop, character, level chunk, animation
    library) is what keeps a pipeline consistent: artists pick a kind, they do
    not pick individual checkboxes.
    """

    name: StringProperty(name="Name", default="Profile")
    description: StringProperty(name="Description", default="")

    # -- destination ---------------------------------------------------------
    dest_dir: StringProperty(
        name="Default Folder",
        description="Folder inside the Godot project this profile exports to, e.g. assets/props. "
                    "Per-collection settings can override it",
        default="assets",
    )
    subfolder_per_asset: BoolProperty(
        name="Folder per Asset",
        description="Export to <folder>/<asset>/<asset>.glb instead of <folder>/<asset>.glb. "
                    "Strongly recommended whenever Godot extracts textures",
        default=True,
    )

    # -- glTF content --------------------------------------------------------
    file_format: EnumProperty(
        name="Format",
        items=[('GLB', ".glb (binary)", "Single binary file"),
               ('GLTF_SEPARATE', ".gltf + .bin + textures",
                "Text glTF, diff friendly, textures written as loose files")],
        default='GLB',
    )
    material_policy: EnumProperty(name="Materials", items=MATERIAL_POLICY_ITEMS, default='EXTERNAL')
    apply_modifiers: BoolProperty(
        name="Apply Modifiers", default=True,
        description="Apply modifiers on export. Note: this disables shape key export")
    export_tangents: BoolProperty(
        name="Export Tangents", default=False,
        description="Export tangents. Usually unnecessary, Godot regenerates them with "
                    "Mikktspace when Ensure Tangents is on")
    export_extras: BoolProperty(
        name="Custom Properties", default=True,
        description="Export Blender custom properties as glTF extras. Godot exposes them as "
                    "node metadata under the 'extras' key")
    export_cameras: BoolProperty(name="Cameras", default=False)
    export_lights: BoolProperty(name="Lights", default=False)
    export_vertex_colors: BoolProperty(
        name="Vertex Colors", default=False,
        description="Export vertex colors when a material uses them")
    export_attributes: BoolProperty(
        name="Mesh Attributes", default=False,
        description="Export custom mesh attributes. Needed if a Godot shader reads them")
    yup: BoolProperty(
        name="+Y Up", default=True,
        description="glTF and Godot convention. Leave enabled")
    use_gpu_instances: BoolProperty(
        name="GPU Instances", default=False,
        description="Export EXT_mesh_gpu_instancing for repeated meshes")

    # -- animation -----------------------------------------------------------
    export_animations: BoolProperty(name="Animations", default=False)
    animation_mode: EnumProperty(
        name="Animation Mode",
        items=[('ACTIONS', "Actions", "Every action, including NLA tracked ones, becomes one animation"),
               ('ACTIVE_ACTIONS', "Active Actions Merged", "Currently assigned actions become one animation"),
               ('NLA_TRACKS', "NLA Tracks", "Every NLA track becomes one animation"),
               ('SCENE', "Scene", "Bake the whole scene into a single animation")],
        default='ACTIONS')
    deform_bones_only: BoolProperty(
        name="Deform Bones Only", default=True,
        description="Skip control bones. Keeps the Godot Skeleton3D small and its bone indices stable")
    rest_position_armature: BoolProperty(
        name="Rest Position Armature", default=True,
        description="Export the armature in rest pose, which is what Godot expects for the bind pose")
    influences: IntProperty(
        name="Bone Influences", default=4, min=1, max=8,
        description="Max bone influences per vertex. Godot handles 4 cheaply")
    optimize_animation: BoolProperty(name="Optimize Animation Size", default=True)

    # -- Godot import options written into the .glb.import -------------------
    write_import_file: BoolProperty(
        name="Write .import Settings", default=True,
        description="Patch the Godot .glb.import file next to the exported asset so import "
                    "options stay in version control and survive a re-export")
    create_import_file: BoolProperty(
        name="Create .import If Missing", default=False,
        description="Write a minimal .import file when Godot has not created one yet. "
                    "Leave off if you prefer to open Godot once and let it generate the file")
    root_type: EnumProperty(name="Root Node", items=PHYSICS_ROOT_ITEMS, default='NONE')
    root_scale: FloatProperty(name="Root Scale", default=1.0, min=0.001, max=1000.0)
    ensure_tangents: BoolProperty(name="Ensure Tangents", default=True)
    generate_lods: BoolProperty(name="Generate LODs", default=True)
    create_shadow_meshes: BoolProperty(name="Create Shadow Meshes", default=True)
    light_bake_mode: EnumProperty(name="Light Baking", items=LIGHT_BAKE_ITEMS, default='DYNAMIC')
    import_animations: BoolProperty(name="Import Animations", default=True)
    animation_fps: IntProperty(name="Animation FPS", default=30, min=1, max=240)
    import_script: StringProperty(
        name="Import Script",
        description="res:// path of an EditorScenePostImport script Godot runs after every import",
        default="")

    # -- materials -----------------------------------------------------------
    material_dir: StringProperty(
        name="Material Folder",
        description="Where external .tres materials live, relative to the Godot project. "
                    "Leave empty to keep them next to the asset",
        default="assets/materials")
    generate_material_stubs: BoolProperty(
        name="Generate Missing .tres", default=True,
        description="Create an empty StandardMaterial3D .tres for materials that do not have one "
                    "yet, so the .import file has something to point at")
    link_external_materials: BoolProperty(
        name="Link External Materials", default=True,
        description="Write _subresources/materials/<name>/use_external into the .import file")

    # -- textures ------------------------------------------------------------
    copy_textures: BoolProperty(
        name="Copy Textures", default=False,
        description="Copy image files used by exported materials into the Godot project, "
                    "skipping files that are already there and identical")
    texture_dir: StringProperty(
        name="Texture Folder",
        description="Destination for copied textures, relative to the Godot project",
        default="assets/textures")


class GP_ObjectSettings(PropertyGroup):
    """Per-object Godot import hints."""

    collision: EnumProperty(name="Godot Node", items=COLLISION_ITEMS, default='NONE')
    export_name: StringProperty(
        name="Export Name",
        description="Override the node name written into the glTF. Empty means the object name",
        default="")


class GP_MaterialSettings(PropertyGroup):
    force_alpha: BoolProperty(
        name="-alpha", default=False,
        description="Append -alpha so Godot forces TRANSPARENCY_ALPHA on this material")
    use_vertex_color: BoolProperty(
        name="-vcol", default=False,
        description="Append -vcol so Godot enables vertex color on this material")
    location: EnumProperty(
        name="Lives", items=MATERIAL_LOCATION_ITEMS, default='SHARED',
        description="Which folder owns this material's .tres and the textures it uses")
    godot_path: StringProperty(
        name="Override Path",
        description="res:// path of the external .tres this material maps to. Non-empty wins "
                    "over Lives; empty means derive the path from Lives",
        default="")


class GP_CollectionSettings(PropertyGroup):
    """Marks a collection as one shippable Godot asset."""

    is_asset: BoolProperty(
        name="Export as Godot Asset", default=False,
        description="Treat this collection as one independent asset: one .glb, one .import, "
                    "one folder in the Godot project")
    profile: StringProperty(
        name="Profile",
        description="Name of the export profile to use. Empty means the first profile",
        default="")
    dest_dir: StringProperty(
        name="Folder",
        description="Override the profile folder. Relative to the Godot project root",
        default="")
    file_name: StringProperty(
        name="File Name",
        description="Override the file name without extension. Empty means the collection name",
        default="")
    at_center: BoolProperty(
        name="Export at Origin", default=True,
        description="Export around the collection's own center instead of the world origin, so "
                    "assets can be laid out anywhere convenient inside the .blend")
    include_children: BoolProperty(
        name="Include Child Collections", default=True)
    skip: BoolProperty(
        name="Skip", default=False,
        description="Temporarily exclude this asset from batch exports")


CLASSES = (
    GP_ExportProfile,
    GP_ObjectSettings,
    GP_MaterialSettings,
    GP_CollectionSettings,
)


def register():
    for cls in CLASSES:
        bpy.utils.register_class(cls)
    bpy.types.Collection.godot = PointerProperty(type=GP_CollectionSettings)
    bpy.types.Object.godot = PointerProperty(type=GP_ObjectSettings)
    bpy.types.Material.godot = PointerProperty(type=GP_MaterialSettings)
    # Godot reads -loop off the animation name, so this is a single flag rather
    # than a property group.
    bpy.types.Action.godot_loop = BoolProperty(
        name="Loop in Godot", default=False,
        description="Append -loop to the animation name so Godot sets the loop flag")


def unregister():
    del bpy.types.Action.godot_loop
    del bpy.types.Material.godot
    del bpy.types.Object.godot
    del bpy.types.Collection.godot
    for cls in reversed(CLASSES):
        bpy.utils.unregister_class(cls)
