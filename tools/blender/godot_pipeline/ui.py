"""Panels: a Godot tab in the 3D view sidebar plus per-datablock property panels."""

import bpy
from bpy.types import Panel

from . import exporter, layers, ops, paths, physics, validate
from .prefs import get_prefs, get_profile

CATEGORY = "Godot"

LEVEL_ICON = {
    validate.ERROR: 'ERROR',
    validate.WARNING: 'ERROR',
    validate.INFO: 'INFO',
}

STATUS_ICON = {
    "ok": 'CHECKMARK',
    "failed": 'ERROR',
    "skipped": 'RADIOBUT_OFF',
    "dry-run": 'GHOST_ENABLED',
}


def _draw_project_status(layout, context):
    prefs = get_prefs(context)
    root = paths.project_root(prefs)
    box = layout.box()
    if paths.is_valid_project(root):
        box.label(text=root, icon='CHECKMARK')
    else:
        box.label(text="Godot project not found", icon='ERROR')
        box.operator("godot_pipeline.detect_project", icon='VIEWZOOM')
        box.label(text="or set it in Preferences > Add-ons", icon='PREFERENCES')
    return prefs, root


class GP_PT_main(Panel):
    bl_label = "Godot Pipeline"
    bl_space_type = 'VIEW_3D'
    bl_region_type = 'UI'
    bl_category = CATEGORY

    def draw(self, context):
        layout = self.layout
        prefs, root = _draw_project_status(layout, context)

        assets = exporter.collect_assets(context.scene)
        layout.label(text="%d asset(s) marked in this scene" % len(assets))

        col = layout.column(align=True)
        col.scale_y = 1.3
        col.operator("godot_pipeline.export_all", icon='EXPORT')
        col.operator("godot_pipeline.export_active", icon='EXPORT')

        row = layout.row(align=True)
        row.operator("godot_pipeline.validate", icon='CHECKMARK')
        layout.prop(prefs, "dry_run")

        layout.separator()
        layout.operator("godot_pipeline.rename_textures", icon='FILE_IMAGE')


class GP_PT_asset(Panel):
    bl_label = "Active Asset"
    bl_space_type = 'VIEW_3D'
    bl_region_type = 'UI'
    bl_category = CATEGORY
    bl_parent_id = "GP_PT_main"

    def draw(self, context):
        draw_collection_settings(self.layout, context, context.collection)


class GP_PT_object(Panel):
    bl_label = "Selected Objects"
    bl_space_type = 'VIEW_3D'
    bl_region_type = 'UI'
    bl_category = CATEGORY
    bl_parent_id = "GP_PT_main"

    def draw(self, context):
        layout = self.layout
        obj = context.active_object
        if obj is None:
            layout.label(text="No active object")
            return

        layout.prop(obj.godot, "collision")
        layout.prop(obj.godot, "export_name")
        layout.label(text="Exports as: " + _export_name(obj), icon='NODETREE')

        layout.separator()
        row = layout.row(align=True)
        op = row.operator("godot_pipeline.set_collision", text="Apply to Selected")
        op.collision = obj.godot.collision

        layout.separator()
        col = layout.column(align=True)
        col.label(text="Batch", icon='OUTLINER_COLLECTION')
        col.operator("godot_pipeline.split_to_collections", icon='OUTLINER_OB_GROUP_INSTANCE')
        count = len(context.selected_objects)
        col.label(text="%d object(s) selected" % count, icon='BLANK1')


def draw_bone(layout, obj, settings):
    """Which bone a PhysicalBone3D drives, and where that answer came from."""
    box = layout.box()
    box.label(text="Ragdoll Bone", icon='BONE_DATA')
    box.prop(settings, "joint_type")

    armature = physics.armature_of(obj)
    if armature is not None:
        box.prop_search(settings, "bone", armature.data, "bones", text="Bone")
    else:
        box.prop(settings, "bone")

    resolved = physics.bone_of(obj)
    if not resolved:
        sub = box.column(align=True)
        sub.alert = True
        sub.label(text="No bone: this body cannot be built", icon='ERROR')
        sub.label(text="Parent the shape to a bone (Ctrl+P)", icon='BLANK1')
        sub.label(text="or pick one above", icon='BLANK1')
    elif not settings.bone:
        box.label(text="From parenting: " + resolved, icon='CHECKMARK')


def draw_layers(layout, context, settings, compact=False):
    """Layer and mask, labelled with the names read out of project.godot."""
    root = paths.project_root(get_prefs(context))
    names = layers.physics_layers(root)
    named = layers.named_indices(names)

    box = layout.box()
    box.label(text="Collision Layers", icon='GRID')

    if named:
        for prop_name, title in (("collision_layer", "Layer"), ("collision_mask", "Mask")):
            col = box.column(align=True)
            col.label(text=title)
            grid = col.grid_flow(row_major=True, columns=1 if compact else 2,
                                 even_columns=True, align=True)
            for index in named:
                grid.prop(settings, prop_name, index=index, text=names[index], toggle=True)
        if not compact:
            # The named layers are the ones anybody should be picking, but a bit
            # outside them still has to be reachable — and visible when it is
            # already set, or it would look like nothing is selected.
            col = box.column(align=True)
            col.label(text="All 32 bits")
            col.prop(settings, "collision_layer", text="")
            col.prop(settings, "collision_mask", text="")
    else:
        box.prop(settings, "collision_layer", text="Layer")
        box.prop(settings, "collision_mask", text="Mask")
        hint = box.column(align=True)
        hint.label(text="No layer names in project.godot", icon='INFO')
        hint.label(text="Name them in Godot to see them here", icon='BLANK1')

    if not compact:
        box.prop(settings, "priority")


def draw_physics(layout, context, obj, compact=False):
    """Body / shape editor for one object."""
    if obj is None:
        layout.label(text="No active object")
        return

    settings = obj.godot_physics
    if settings.is_proxy:
        layout.label(text="Collision proxy of %s"
                          % (obj.parent.name if obj.parent else "nothing"), icon='MOD_PHYSICS')

    col = layout.column(align=True)
    col.prop(settings, "body")
    col.prop(settings, "shape")

    if settings.shape != 'NONE':
        sub = col.column(align=True)
        sub.prop(settings, "margin")
        # A ragdoll bone is normally a blank, so Keep Mesh is a real choice
        # there too — unlike a StaticBody3D, where the node is the visual.
        if settings.body in ('NONE', 'PHYSICAL_BONE'):
            sub.prop(settings, "keep_mesh")
    if settings.body in physics.MASSIVE_BODIES:
        col.prop(settings, "mass")

    if settings.body == 'PHYSICAL_BONE':
        draw_bone(layout, obj, settings)

    if settings.shape in physics.STATIC_ONLY_SHAPES and settings.body in physics.MOVING_BODIES:
        box = layout.box()
        box.alert = True
        box.label(text="Trimesh cannot move", icon='ERROR')
        box.label(text="Use Simple (Convex) on a moving body")

    if settings.body != 'NONE':
        draw_layers(layout, context, settings, compact)

    if physics.has_physics(obj):
        box = layout.box()
        box.label(text="Written to custom properties", icon='RNA')
        grid = box.column(align=True)
        for key in physics.ALL_KEYS:
            if key in obj:
                grid.label(text="%s = %s" % (key, obj[key]), icon='BLANK1')


class GP_PT_collisions(Panel):
    bl_label = "Collisions"
    bl_space_type = 'VIEW_3D'
    bl_region_type = 'UI'
    bl_category = CATEGORY

    def draw(self, context):
        layout = self.layout

        col = layout.column(align=True)
        col.scale_y = 1.2
        col.operator("godot_pipeline.add_collision", icon='MOD_PHYSICS')
        row = layout.row(align=True)
        row.operator("godot_pipeline.refit_collision", icon='FULLSCREEN_EXIT')
        row.operator("godot_pipeline.copy_collision", icon='DUPLICATE')
        row = layout.row(align=True)
        row.operator("godot_pipeline.select_collision", icon='RESTRICT_SELECT_OFF')
        row.operator("godot_pipeline.clear_collision", icon='TRASH')

        layout.separator()
        layout.label(text="Preview", icon='HIDE_OFF')
        row = layout.row(align=True)
        for mode, label, _description in physics.DISPLAY_ITEMS:
            row.operator("godot_pipeline.collision_display", text=label).mode = mode

        layout.separator()
        draw_physics(layout, context, context.active_object)


class GP_PT_collision_setup(Panel):
    bl_label = "Godot Side"
    bl_space_type = 'VIEW_3D'
    bl_region_type = 'UI'
    bl_category = CATEGORY
    bl_parent_id = "GP_PT_collisions"
    bl_options = {'DEFAULT_CLOSED'}

    def draw(self, context):
        layout = self.layout
        prefs = get_prefs(context)

        configured = [p for p in prefs.profiles if p.import_script]
        box = layout.box()
        if configured and len(configured) == len(prefs.profiles):
            box.label(text="Import script set on all profiles", icon='CHECKMARK')
            box.label(text=configured[0].import_script, icon='BLANK1')
        else:
            box.alert = True
            box.label(text="No import script: this metadata", icon='ERROR')
            box.label(text="does nothing in Godot yet", icon='BLANK1')
        layout.operator("godot_pipeline.install_import_script", icon='FILE_SCRIPT')

        col = layout.column(align=True)
        col.label(text="Custom properties reach Godot as", icon='INFO')
        col.label(text="node metadata; the script turns", icon='BLANK1')
        col.label(text="them into real physics nodes.", icon='BLANK1')


class GP_PT_report(Panel):
    bl_label = "Report"
    bl_space_type = 'VIEW_3D'
    bl_region_type = 'UI'
    bl_category = CATEGORY
    bl_parent_id = "GP_PT_main"
    bl_options = {'DEFAULT_CLOSED'}

    def draw(self, context):
        layout = self.layout

        if ops.LAST_ISSUES:
            box = layout.box()
            box.label(text="Validation", icon='CHECKMARK')
            for issue in ops.LAST_ISSUES[:40]:
                row = box.row()
                row.alert = issue.level == validate.ERROR
                label = "%s: %s" % (issue.asset, issue.message) if issue.asset else issue.message
                row.label(text=label, icon=LEVEL_ICON.get(issue.level, 'INFO'))
            if len(ops.LAST_ISSUES) > 40:
                box.label(text="... %d more, see the console" % (len(ops.LAST_ISSUES) - 40))

        if ops.LAST_RESULTS:
            box = layout.box()
            box.label(text="Last Export", icon='EXPORT')
            for result in ops.LAST_RESULTS:
                row = box.row()
                row.alert = result.status == "failed"
                row.label(text="%s  %s" % (result.collection.name, result.path),
                          icon=STATUS_ICON.get(result.status, 'DOT'))
                for message in result.messages:
                    box.label(text="    " + message, icon='BLANK1')

        if not ops.LAST_ISSUES and not ops.LAST_RESULTS:
            layout.label(text="Nothing run yet")


def _export_name(obj):
    from .naming import object_export_name
    return object_export_name(obj, obj.godot)


def draw_collection_settings(layout, context, collection):
    if collection is None:
        layout.label(text="No active collection")
        return

    settings = collection.godot
    layout.prop(settings, "is_asset", text="Export as Godot Asset", toggle=False)
    if not settings.is_asset:
        layout.operator("godot_pipeline.mark_asset", icon='ADD')
        return

    prefs = get_prefs(context)
    profile = get_profile(prefs, settings.profile)

    col = layout.column(align=True)
    col.prop_search(settings, "profile", prefs, "profiles", icon='PRESET')
    col.prop(settings, "dest_dir", placeholder=profile.dest_dir if profile else "")
    col.prop(settings, "file_name", placeholder=collection.name)

    col = layout.column(align=True)
    col.prop(settings, "at_center")
    col.prop(settings, "include_children")
    col.prop(settings, "skip")

    if profile is None:
        layout.label(text="No export profile defined", icon='ERROR')
        return

    root = paths.project_root(prefs)
    if paths.is_valid_project(root):
        abs_file, res_file, abs_dir = exporter.asset_paths(root, profile, collection)
        box = layout.box()
        box.label(text=res_file, icon='FILE_3D')
        box.label(text="Materials: " + _policy_label(profile), icon='MATERIAL')
        row = box.row()
        row.enabled = bool(abs_dir)
        row.operator("godot_pipeline.open_folder", icon='FILE_FOLDER').path = abs_dir


def _policy_label(profile):
    return {
        'EXTERNAL': "Godot owns them (no images in the file)",
        'EXTRACT': "extracted next to the file",
        'EMBED': "embedded in the scene",
    }[profile.material_policy]


class GP_PT_collection_props(Panel):
    bl_label = "Godot"
    bl_space_type = 'PROPERTIES'
    bl_region_type = 'WINDOW'
    bl_context = "collection"

    def draw(self, context):
        draw_collection_settings(self.layout, context, context.collection)


class GP_PT_object_props(Panel):
    bl_label = "Godot"
    bl_space_type = 'PROPERTIES'
    bl_region_type = 'WINDOW'
    bl_context = "object"

    @classmethod
    def poll(cls, context):
        return context.object is not None

    def draw(self, context):
        layout = self.layout
        obj = context.object
        layout.prop(obj.godot, "collision")
        layout.prop(obj.godot, "export_name")
        layout.label(text="Exports as: " + _export_name(obj), icon='NODETREE')

        if obj.animation_data and obj.animation_data.action:
            layout.separator()
            layout.prop(obj.animation_data.action, "godot_loop")

        layout.separator()
        layout.label(text="Physics", icon='MOD_PHYSICS')
        draw_physics(layout, context, obj, compact=True)


class GP_PT_material_props(Panel):
    bl_label = "Godot"
    bl_space_type = 'PROPERTIES'
    bl_region_type = 'WINDOW'
    bl_context = "material"

    @classmethod
    def poll(cls, context):
        return context.material is not None

    def draw(self, context):
        layout = self.layout
        mat = context.material
        row = layout.row(align=True)
        row.prop(mat.godot, "force_alpha", toggle=True)
        row.prop(mat.godot, "use_vertex_color", toggle=True)

        layout.separator()
        layout.prop(mat.godot, "location")
        box = layout.box()
        if mat.godot.godot_path:
            box.label(text="Override wins:", icon='FILE_TICK')
            box.label(text=mat.godot.godot_path, icon='BLANK1')
        elif mat.godot.location == 'ASSET':
            box.label(text="<asset>/materials/%s.tres" % mat.name, icon='FILE_TICK')
            box.label(text="textures follow it into <asset>/textures", icon='BLANK1')
        else:
            box.label(text="<profile material folder>/%s.tres" % mat.name, icon='FILE_TICK')
            box.label(text="textures go to the shared texture folder", icon='BLANK1')
        layout.prop(mat.godot, "godot_path")

        from .naming import material_export_name
        layout.label(text="Exports as: " + material_export_name(mat, mat.godot), icon='MATERIAL')


CLASSES = (
    GP_PT_main,
    GP_PT_asset,
    GP_PT_object,
    GP_PT_report,
    GP_PT_collisions,
    GP_PT_collision_setup,
    GP_PT_collection_props,
    GP_PT_object_props,
    GP_PT_material_props,
)


def register():
    for cls in CLASSES:
        bpy.utils.register_class(cls)


def unregister():
    for cls in reversed(CLASSES):
        bpy.utils.unregister_class(cls)
