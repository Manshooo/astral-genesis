"""Operators."""

import os
import subprocess
import sys

import bpy
from bpy.props import BoolProperty, EnumProperty, FloatProperty, IntProperty, StringProperty
from bpy.types import Operator

from . import exporter, paths, physics, prefs as prefs_mod, ucupaint, validate
from .naming import COLLISION_ITEMS

# Last run, so the sidebar can show what happened without a modal dialog.
LAST_RESULTS = []
LAST_ISSUES = []


def _prefs(context):
    return prefs_mod.get_prefs(context)


class GP_OT_detect_project(Operator):
    bl_idname = "godot_pipeline.detect_project"
    bl_label = "Detect Godot Project"
    bl_description = "Search upwards from this .blend for a folder containing project.godot"

    def execute(self, context):
        prefs = _prefs(context)
        root = paths.find_project_root(bpy.data.filepath)
        if not root:
            self.report({'ERROR'}, "No project.godot found above this .blend")
            return {'CANCELLED'}
        prefs.godot_project = root
        self.report({'INFO'}, "Godot project: " + root)
        return {'FINISHED'}


# -- profiles ---------------------------------------------------------------

class GP_OT_profile_add(Operator):
    bl_idname = "godot_pipeline.profile_add"
    bl_label = "Add Profile"
    bl_description = "Add a new export profile"

    def execute(self, context):
        prefs = _prefs(context)
        profile = prefs.profiles.add()
        profile.name = "Profile %d" % len(prefs.profiles)
        prefs.active_profile = len(prefs.profiles) - 1
        return {'FINISHED'}


class GP_OT_profile_remove(Operator):
    bl_idname = "godot_pipeline.profile_remove"
    bl_label = "Remove Profile"
    bl_description = "Remove the selected export profile"

    def execute(self, context):
        prefs = _prefs(context)
        if not len(prefs.profiles):
            return {'CANCELLED'}
        prefs.profiles.remove(prefs.active_profile)
        prefs.active_profile = max(0, prefs.active_profile - 1)
        return {'FINISHED'}


class GP_OT_profile_reset(Operator):
    bl_idname = "godot_pipeline.profile_reset"
    bl_label = "Reset Profiles"
    bl_description = "Replace all profiles with the built-in defaults"
    bl_options = {'REGISTER', 'UNDO'}

    def invoke(self, context, event):
        return context.window_manager.invoke_confirm(self, event)

    def execute(self, context):
        prefs_mod.reset_profiles(_prefs(context))
        return {'FINISHED'}


class GP_OT_config_save(Operator):
    bl_idname = "godot_pipeline.config_save"
    bl_label = "Save to Project"
    bl_description = ("Write the profiles to godot_pipeline.json next to project.godot "
                      "so they can be committed and shared")

    def execute(self, context):
        try:
            path = prefs_mod.save_config(_prefs(context))
        except (RuntimeError, OSError) as error:
            self.report({'ERROR'}, str(error))
            return {'CANCELLED'}
        self.report({'INFO'}, "Saved " + path)
        return {'FINISHED'}


class GP_OT_config_load(Operator):
    bl_idname = "godot_pipeline.config_load"
    bl_label = "Load from Project"
    bl_description = "Replace the profiles with the ones in godot_pipeline.json"

    def invoke(self, context, event):
        return context.window_manager.invoke_confirm(self, event)

    def execute(self, context):
        try:
            path = prefs_mod.load_config(_prefs(context))
        except (RuntimeError, OSError, ValueError) as error:
            self.report({'ERROR'}, str(error))
            return {'CANCELLED'}
        self.report({'INFO'}, "Loaded " + path)
        return {'FINISHED'}


# -- marking assets ---------------------------------------------------------

def _profile_items(self, context):
    prefs = _prefs(context)
    return [(p.name, p.name, p.description) for p in prefs.profiles] or [('', "No profiles", "")]


class GP_OT_mark_asset(Operator):
    bl_idname = "godot_pipeline.mark_asset"
    bl_label = "Mark as Godot Asset"
    bl_description = "Mark the active collection as one shippable Godot asset"
    bl_options = {'REGISTER', 'UNDO'}

    profile: EnumProperty(name="Profile", items=_profile_items)

    @classmethod
    def poll(cls, context):
        return context.collection is not None

    def invoke(self, context, event):
        return context.window_manager.invoke_props_dialog(self)

    def execute(self, context):
        collection = context.collection
        collection.godot.is_asset = True
        collection.godot.profile = self.profile
        self.report({'INFO'}, "%s -> %s" % (collection.name, self.profile))
        return {'FINISHED'}


class GP_OT_set_collision(Operator):
    bl_idname = "godot_pipeline.set_collision"
    bl_label = "Set Godot Node Type"
    bl_description = "Apply a Godot import hint to every selected object"
    bl_options = {'REGISTER', 'UNDO'}

    collision: EnumProperty(name="Godot Node", items=COLLISION_ITEMS, default='COL')

    @classmethod
    def poll(cls, context):
        return bool(context.selected_objects)

    def execute(self, context):
        for obj in context.selected_objects:
            obj.godot.collision = self.collision
        self.report({'INFO'}, "%d object(s) set to %s" % (len(context.selected_objects), self.collision))
        return {'FINISHED'}


class GP_OT_split_to_collections(Operator):
    """Give every selected object its own collection, nested where it already lived."""

    bl_idname = "godot_pipeline.split_to_collections"
    bl_label = "Collection per Object"
    bl_description = ("Create one collection per selected object, named after the object with "
                      "Godot import suffixes removed, and move the object into it. The new "
                      "collection is nested inside the collection the object came from")
    bl_options = {'REGISTER', 'UNDO'}

    strip_suffixes: BoolProperty(
        name="Strip Godot Suffixes", default=True,
        description="Drop -col, -colonly, -navmesh and the rest from the collection name, so a "
                    "mesh and its collision shape land in the same collection")
    keep_duplicate_marker: BoolProperty(
        name="Keep .001 Suffix", default=True,
        description="Keep Blender's duplicate marker in the collection name. Turn off to merge "
                    "Barrel, Barrel.001 and Barrel.002 into a single collection")
    reuse_existing: BoolProperty(
        name="Reuse Existing", default=True,
        description="If the parent already has a collection with that name, move the object into "
                    "it instead of creating a second one")
    include_child_objects: BoolProperty(
        name="Take Child Objects", default=False,
        description="Also move each object's parented children, even when they are not selected")
    mark_as_asset: BoolProperty(
        name="Mark as Godot Asset", default=False,
        description="Flag every new collection for export straight away")
    profile: EnumProperty(name="Profile", items=_profile_items)

    @classmethod
    def poll(cls, context):
        return bool(context.selected_objects)

    def draw(self, context):
        layout = self.layout
        layout.prop(self, "strip_suffixes")
        sub = layout.column()
        sub.active = self.strip_suffixes
        sub.prop(self, "keep_duplicate_marker")
        layout.prop(self, "reuse_existing")
        layout.prop(self, "include_child_objects")
        layout.separator()
        layout.prop(self, "mark_as_asset")
        sub = layout.column()
        sub.active = self.mark_as_asset
        sub.prop(self, "profile")

    def invoke(self, context, event):
        return context.window_manager.invoke_props_dialog(self, width=340)

    # -- helpers ------------------------------------------------------------

    def _target_name(self, obj):
        from .naming import strip_godot_suffixes
        if not self.strip_suffixes:
            return obj.name
        return strip_godot_suffixes(obj.name, keep_duplicate_marker=self.keep_duplicate_marker)

    @staticmethod
    def _parent_of(context, obj):
        """The collection the object is moved out of, and therefore nested under.

        Prefers the collection the user is actually working in, so the result
        matches what the outliner shows as "current".
        """
        current = list(obj.users_collection)
        if not current:
            return None
        active = context.view_layer.active_layer_collection
        if active is not None and active.collection in current:
            return active.collection
        return current[0]

    def _roots(self, context):
        """Selected objects, minus those whose parent is also selected.

        Only relevant with Take Child Objects: a child that travels with its
        parent must not also claim a collection of its own.
        """
        selected = list(context.selected_objects)
        if not self.include_child_objects:
            return sorted(selected, key=lambda o: o.name)
        chosen = set(selected)
        roots = []
        for obj in selected:
            parent = obj.parent
            while parent is not None and parent not in chosen:
                parent = parent.parent
            if parent is None:
                roots.append(obj)
        return sorted(roots, key=lambda o: o.name)

    # -- execute ------------------------------------------------------------

    def execute(self, context):
        created = 0
        reused = 0
        moved = 0
        already = 0
        warnings = []

        for obj in self._roots(context):
            parent = self._parent_of(context, obj)
            if parent is None:
                warnings.append("%s is not linked to any collection" % obj.name)
                continue

            name = self._target_name(obj)
            if any(coll.name == name for coll in obj.users_collection):
                already += 1
                continue

            target = None
            if self.reuse_existing:
                target = next((c for c in parent.children if c.name == name), None)
            if target is not None:
                reused += 1
            else:
                target = bpy.data.collections.new(name)
                if target.name != name:
                    warnings.append("%r was taken, created %r instead" % (name, target.name))
                parent.children.link(target)
                created += 1
                if self.mark_as_asset and self.profile:
                    target.godot.is_asset = True
                    target.godot.profile = self.profile

            travellers = [obj]
            if self.include_child_objects:
                travellers += [child for child in obj.children_recursive]

            for traveller in travellers:
                if target in traveller.users_collection:
                    continue
                for collection in list(traveller.users_collection):
                    collection.objects.unlink(traveller)
                target.objects.link(traveller)
                moved += 1

        for message in warnings:
            print("[godot_pipeline] %s" % message)

        if not created and not reused and not moved:
            self.report({'WARNING'}, "Nothing to do (%d object(s) already in place)" % already)
            return {'CANCELLED'}

        summary = "%d collection(s) created" % created
        if reused:
            summary += ", %d reused" % reused
        summary += ", %d object(s) moved" % moved
        if already:
            summary += ", %d already in place" % already
        if warnings:
            summary += ", %d warning(s) in the console" % len(warnings)
        self.report({'WARNING'} if warnings else {'INFO'}, summary)
        return {'FINISHED'}


# -- collisions -------------------------------------------------------------

class GP_OT_add_collision(Operator):
    """Give the selected objects a body and/or a collision shape."""

    bl_idname = "godot_pipeline.add_collision"
    bl_label = "Add Collision"
    bl_description = ("Set the Godot physics body on the selected objects and build a fitted "
                      "collision shape for each. Everything is stored in custom properties, "
                      "object names are left alone")
    bl_options = {'REGISTER', 'UNDO'}

    body: EnumProperty(name="Body", items=physics.BODY_ITEMS, default='STATIC')
    shape: EnumProperty(name="Collision", items=physics.SHAPE_ITEMS, default='BOX')
    source: EnumProperty(
        name="Shape From",
        items=[('PROXY', "New Child Object",
                "Build a separate collision object fitted to the bounds and parent it to the "
                "object. Editable, and the usual choice"),
               ('SELF', "This Object",
                "Use the object's own mesh as the collision shape. Only meaningful for "
                "Simple (Convex) and Trimesh (Concave)")],
        default='PROXY')
    margin: FloatProperty(name="Margin", default=0.04, min=0.0, max=1.0, step=1, precision=4)
    segments: IntProperty(name="Segments", default=16, min=6, max=64,
                          description="Resolution of round proxy shapes")
    replace: BoolProperty(
        name="Replace Existing", default=True,
        description="Remove collision proxies the object already has")

    @classmethod
    def poll(cls, context):
        return bool(context.selected_objects)

    def invoke(self, context, event):
        return context.window_manager.invoke_props_dialog(self, width=340)

    def draw(self, context):
        layout = self.layout
        layout.prop(self, "body")
        layout.prop(self, "shape")
        sub = layout.column()
        sub.active = self.shape != 'NONE'
        sub.prop(self, "source")
        sub.prop(self, "margin")
        row = sub.row()
        row.active = self.source == 'PROXY' and self.shape in physics.PRIMITIVE_SHAPES
        row.prop(self, "segments")
        layout.prop(self, "replace")

        if self.source == 'SELF' and self.shape in physics.PRIMITIVE_SHAPES:
            layout.label(text="Primitives need a child object", icon='ERROR')
        if self.shape in physics.STATIC_ONLY_SHAPES and self.body in physics.MOVING_BODIES:
            layout.label(text="Trimesh cannot move; use Convex", icon='ERROR')

    def execute(self, context):
        if self.source == 'SELF' and self.shape in physics.PRIMITIVE_SHAPES:
            self.report({'ERROR'}, "Primitive shapes need their own child object")
            return {'CANCELLED'}
        if self.shape in physics.STATIC_ONLY_SHAPES and self.body in physics.MOVING_BODIES:
            self.report({'ERROR'}, "ConcavePolygonShape3D is only valid on a static body")
            return {'CANCELLED'}

        targets = [obj for obj in context.selected_objects if not physics.is_proxy(obj)]
        if not targets:
            self.report({'WARNING'}, "Only collision proxies are selected")
            return {'CANCELLED'}

        made = 0
        for obj in targets:
            obj.godot_physics.body = self.body

            if self.replace:
                for child in [c for c in obj.children if physics.is_proxy(c)]:
                    bpy.data.objects.remove(child, do_unlink=True)

            if self.shape == 'NONE':
                obj.godot_physics.shape = 'NONE'
                physics.write_custom_props(obj)
                continue

            if self.source == 'SELF':
                obj.godot_physics.shape = self.shape
                obj.godot_physics.margin = self.margin
                physics.write_custom_props(obj)
                made += 1
                continue

            if obj.type != 'MESH':
                self.report({'WARNING'}, "%s has no mesh to fit a shape to" % obj.name)
                continue
            proxy = physics.create_proxy(obj, self.shape, self.margin, self.segments)
            if proxy is not None:
                made += 1

        self.report({'INFO'}, "%d object(s) set up, %d shape(s) built" % (len(targets), made))
        return {'FINISHED'}


class GP_OT_refit_collision(Operator):
    bl_idname = "godot_pipeline.refit_collision"
    bl_label = "Refit Shapes"
    bl_description = "Rebuild the selected collision proxies against their parent's current bounds"
    bl_options = {'REGISTER', 'UNDO'}

    segments: IntProperty(name="Segments", default=16, min=6, max=64)

    @classmethod
    def poll(cls, context):
        return bool(context.selected_objects)

    def execute(self, context):
        proxies = physics.iter_proxies(context.selected_objects)
        for obj in context.selected_objects:
            proxies += [c for c in obj.children
                        if physics.is_proxy(c) and c not in proxies]
        done = sum(1 for proxy in proxies if physics.refit_proxy(proxy, self.segments))
        if not done:
            self.report({'WARNING'}, "No collision proxies in the selection")
            return {'CANCELLED'}
        self.report({'INFO'}, "%d shape(s) refitted" % done)
        return {'FINISHED'}


class GP_OT_clear_collision(Operator):
    bl_idname = "godot_pipeline.clear_collision"
    bl_label = "Clear Collision"
    bl_description = "Delete the collision proxies of the selected objects and clear their settings"
    bl_options = {'REGISTER', 'UNDO'}

    @classmethod
    def poll(cls, context):
        return bool(context.selected_objects)

    def execute(self, context):
        removed = 0
        cleared = 0
        for obj in list(context.selected_objects):
            for child in [c for c in obj.children if physics.is_proxy(c)]:
                bpy.data.objects.remove(child, do_unlink=True)
                removed += 1
            if physics.is_proxy(obj):
                bpy.data.objects.remove(obj, do_unlink=True)
                removed += 1
                continue
            if physics.has_physics(obj):
                obj.godot_physics.body = 'NONE'
                obj.godot_physics.shape = 'NONE'
                physics.clear_custom_props(obj)
                cleared += 1
        self.report({'INFO'}, "%d proxy(ies) removed, %d object(s) cleared" % (removed, cleared))
        return {'FINISHED'}


class GP_OT_copy_collision(Operator):
    bl_idname = "godot_pipeline.copy_collision"
    bl_label = "Copy to Selected"
    bl_description = ("Apply the active object's collision setup to every other selected object, "
                      "refitting each shape to its own bounds")
    bl_options = {'REGISTER', 'UNDO'}

    @classmethod
    def poll(cls, context):
        return context.active_object is not None and len(context.selected_objects) > 1

    def execute(self, context):
        source = context.active_object
        shapes = [c for c in source.children if physics.is_proxy(c)]
        done = 0
        for obj in context.selected_objects:
            if obj is source or physics.is_proxy(obj):
                continue
            obj.godot_physics.body = source.godot_physics.body
            obj.godot_physics.shape = source.godot_physics.shape
            obj.godot_physics.margin = source.godot_physics.margin
            obj.godot_physics.mass = source.godot_physics.mass
            obj.godot_physics.collision_layer = source.godot_physics.collision_layer
            obj.godot_physics.collision_mask = source.godot_physics.collision_mask
            physics.write_custom_props(obj)

            for child in [c for c in obj.children if physics.is_proxy(c)]:
                bpy.data.objects.remove(child, do_unlink=True)
            if obj.type == 'MESH':
                for template in shapes:
                    physics.create_proxy(obj, template.godot_physics.shape,
                                         template.godot_physics.margin)
            done += 1
        self.report({'INFO'}, "copied to %d object(s)" % done)
        return {'FINISHED'}


class GP_OT_select_collision(Operator):
    bl_idname = "godot_pipeline.select_collision"
    bl_label = "Select Proxies"
    bl_description = "Select every collision proxy in the scene"
    bl_options = {'REGISTER', 'UNDO'}

    def execute(self, context):
        count = 0
        for obj in context.view_layer.objects:
            selected = physics.is_proxy(obj)
            try:
                obj.select_set(selected)
            except RuntimeError:
                continue
            count += int(selected)
        self.report({'INFO'}, "%d proxy(ies) selected" % count)
        return {'FINISHED'}


class GP_OT_collision_display(Operator):
    bl_idname = "godot_pipeline.collision_display"
    bl_label = "Collision Display"
    bl_description = "Change how collision proxies are drawn in the viewport"
    bl_options = {'REGISTER', 'UNDO'}

    mode: EnumProperty(name="Mode", items=physics.DISPLAY_ITEMS, default='WIRE')

    def execute(self, context):
        proxies = [obj for obj in bpy.data.objects if physics.is_proxy(obj)]
        for obj in proxies:
            physics.apply_display(obj, self.mode)

        if self.mode == 'SOLID':
            # Solid shading paints per-material by default, so switch the
            # visible viewports to object colour or the blue never shows.
            for area in getattr(context.screen, "areas", []):
                if area.type == 'VIEW_3D':
                    area.spaces.active.shading.color_type = 'OBJECT'

        if not proxies:
            self.report({'WARNING'}, "No collision proxies in this file")
            return {'CANCELLED'}
        self.report({'INFO'}, "%d proxy(ies) set to %s" % (len(proxies), self.mode.lower()))
        return {'FINISHED'}


# -- textures ---------------------------------------------------------------

class GP_OT_rename_textures(Operator):
    """Rename baked textures to T_<base>_<map>."""

    bl_idname = "godot_pipeline.rename_textures"
    bl_label = "Rename Textures"
    bl_description = ("Rename Ucupaint's baked images to the project convention "
                      "(T_door_albedo, T_door_orm, T_door_n), files on disk included")
    bl_options = {'REGISTER', 'UNDO'}

    scope: EnumProperty(
        name="Images",
        items=[('SELECTED', "Selected Objects", "Images used by the selected objects' materials"),
               ('ALL', "Whole File", "Every image datablock in this .blend")],
        default='SELECTED')
    rename_files: BoolProperty(
        name="Rename Files on Disk", default=True,
        description="Rename the image file too and repoint the datablock at it. Without this the "
                    "old name is what reaches Godot, because the exporter copies files by name")
    base: StringProperty(
        name="Base Name", default="",
        description="Override the asset part of the name. Empty derives it from the image, "
                    "dropping the MAT_ prefix: «MAT_door Color» becomes T_door_albedo")

    def _images(self, context):
        if self.scope == 'ALL':
            return list(bpy.data.images)
        return ucupaint.images_of_materials(
            ucupaint.materials_of_objects(context.selected_objects))

    def _plan(self, context):
        return ucupaint.plan_renames(self._images(context), self.base.strip(), self.rename_files)

    def invoke(self, context, event):
        return context.window_manager.invoke_props_dialog(self, width=460)

    def draw(self, context):
        layout = self.layout
        layout.prop(self, "scope")
        layout.prop(self, "rename_files")
        layout.prop(self, "base")

        plans, skipped = self._plan(context)
        layout.separator()

        if plans:
            box = layout.box()
            box.label(text="Переименуется (%d)" % len(plans), icon='FILE_IMAGE')
            for plan in plans[:14]:
                row = box.row()
                row.alert = not plan.canonical
                text = "%s  ->  %s" % (plan.image.name, plan.new_name)
                if plan.note:
                    text += "   (%s)" % plan.note
                row.label(text=text, icon='BLANK1')
            if len(plans) > 14:
                box.label(text="… ещё %d" % (len(plans) - 14), icon='BLANK1')

            stray = [p for p in plans if not p.canonical]
            if stray:
                warn = layout.box()
                warn.alert = True
                warn.label(text="Вне конвенции §6: %s" % ", ".join(
                    sorted({p.suffix for p in stray})), icon='ERROR')
                warn.label(text="AO, roughness и metallic должны быть упакованы в ORM",
                           icon='BLANK1')
        else:
            layout.label(text="Нечего переименовывать", icon='CHECKMARK')

        if skipped:
            box = layout.box()
            box.label(text="Пропущено (%d)" % len(skipped), icon='RADIOBUT_OFF')
            for name, reason in skipped[:8]:
                box.label(text="%s — %s" % (name, reason), icon='BLANK1')

    def execute(self, context):
        plans, _skipped = self._plan(context)
        if not plans:
            self.report({'WARNING'}, "Нечего переименовывать")
            return {'CANCELLED'}

        done = 0
        problems = []
        for plan in plans:
            error = ucupaint.apply_plan(plan)
            if error:
                problems.append("%s: %s" % (plan.image.name, error))
            else:
                done += 1

        for message in problems:
            print("[godot_pipeline] %s" % message)
        if problems:
            self.report({'WARNING'}, "%d переименовано, %d с ошибкой (см. консоль)"
                        % (done, len(problems)))
        else:
            self.report({'INFO'}, "%d текстур(ы) переименовано" % done)
        return {'FINISHED'}


class GP_OT_install_import_script(Operator):
    bl_idname = "godot_pipeline.install_import_script"
    bl_label = "Install Godot Import Script"
    bl_description = ("Copy collision_post_import.gd into the Godot project and point every "
                      "profile at it. Without this script the collision metadata does nothing")

    target: StringProperty(default="addons/godot_pipeline/collision_post_import.gd")

    def execute(self, context):
        prefs = _prefs(context)
        root = paths.project_root(prefs)
        if not paths.is_valid_project(root):
            self.report({'ERROR'}, "Godot project root is not set")
            return {'CANCELLED'}

        source = os.path.join(os.path.dirname(__file__), "godot", "collision_post_import.gd")
        if not os.path.isfile(source):
            self.report({'ERROR'}, "collision_post_import.gd is missing from the add-on")
            return {'CANCELLED'}

        rel = paths.clean_rel_dir(os.path.dirname(self.target))
        dest_dir = os.path.join(root, rel.replace("/", os.sep))
        paths.ensure_dir(dest_dir)
        dest = os.path.join(dest_dir, os.path.basename(self.target))
        with open(source, "r", encoding="utf-8") as handle:
            body = handle.read()
        with open(dest, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(body)

        res_path = paths.rel_to_res(root, dest)
        for profile in prefs.profiles:
            profile.import_script = res_path
        self.report({'INFO'}, "Installed %s and set it on %d profile(s)"
                    % (res_path, len(prefs.profiles)))
        return {'FINISHED'}


# -- validation and export --------------------------------------------------

class GP_OT_validate(Operator):
    bl_idname = "godot_pipeline.validate"
    bl_label = "Validate Assets"
    bl_description = "Check every marked collection for problems that would import badly"

    def execute(self, context):
        global LAST_ISSUES
        prefs = _prefs(context)
        collections = exporter.collect_assets(context.scene)
        LAST_ISSUES = validate.validate(context, prefs, collections)

        errors = sum(1 for i in LAST_ISSUES if i.level == validate.ERROR)
        warnings = sum(1 for i in LAST_ISSUES if i.level == validate.WARNING)
        for issue in LAST_ISSUES:
            print("[godot_pipeline] %s %s: %s"
                  % (issue.level, issue.asset or "-", issue.message))
        if errors:
            self.report({'ERROR'}, "%d error(s), %d warning(s). See the Godot panel" % (errors, warnings))
        elif warnings:
            self.report({'WARNING'}, "%d warning(s). See the Godot panel" % warnings)
        else:
            self.report({'INFO'}, "%d asset(s) look fine" % len(collections))
        return {'FINISHED'}


class _ExportBase(Operator):
    bl_options = {'REGISTER'}

    def _run(self, context, collections):
        global LAST_RESULTS, LAST_ISSUES
        prefs = _prefs(context)

        if not collections:
            self.report({'WARNING'}, "Nothing marked 'Export as Godot Asset'")
            return {'CANCELLED'}

        LAST_ISSUES = validate.validate(context, prefs, collections)
        blocking = [i for i in LAST_ISSUES if i.level == validate.ERROR]
        if blocking:
            for issue in blocking:
                print("[godot_pipeline] ERROR %s: %s" % (issue.asset or "-", issue.message))
            self.report({'ERROR'},
                        "%d blocking issue(s), export aborted. See the Godot panel" % len(blocking))
            return {'CANCELLED'}

        results, fatal = exporter.export_many(context, prefs, collections)
        LAST_RESULTS = results
        if fatal:
            self.report({'ERROR'}, fatal)
            return {'CANCELLED'}

        if prefs.verbose:
            for result in results:
                print("[godot_pipeline] %-9s %-28s %s"
                      % (result.status, result.collection.name, result.path))
                for message in result.messages:
                    print("[godot_pipeline]           - %s" % message)

        failed = [r for r in results if r.status == "failed"]
        level = {'ERROR'} if failed else {'INFO'}
        self.report(level, exporter.format_report(results))
        return {'FINISHED'}


class GP_OT_export_all(_ExportBase):
    bl_idname = "godot_pipeline.export_all"
    bl_label = "Export All Assets"
    bl_description = "Export every collection marked as a Godot asset in this scene"

    def execute(self, context):
        return self._run(context, exporter.collect_assets(context.scene))


class GP_OT_export_active(_ExportBase):
    bl_idname = "godot_pipeline.export_active"
    bl_label = "Export Active Asset"
    bl_description = "Export only the active collection"

    @classmethod
    def poll(cls, context):
        return context.collection is not None and context.collection.godot.is_asset

    def execute(self, context):
        return self._run(context, [context.collection])


class GP_OT_open_folder(Operator):
    bl_idname = "godot_pipeline.open_folder"
    bl_label = "Open Output Folder"
    bl_description = "Open the folder this asset exports to"

    path: StringProperty(default="")

    def execute(self, context):
        target = self.path
        if not target or not os.path.isdir(target):
            self.report({'ERROR'}, "Folder does not exist yet")
            return {'CANCELLED'}
        if sys.platform == "win32":
            os.startfile(target)
        elif sys.platform == "darwin":
            subprocess.Popen(["open", target])
        else:
            subprocess.Popen(["xdg-open", target])
        return {'FINISHED'}


CLASSES = (
    GP_OT_detect_project,
    GP_OT_profile_add,
    GP_OT_profile_remove,
    GP_OT_profile_reset,
    GP_OT_config_save,
    GP_OT_config_load,
    GP_OT_mark_asset,
    GP_OT_set_collision,
    GP_OT_split_to_collections,
    GP_OT_add_collision,
    GP_OT_refit_collision,
    GP_OT_clear_collision,
    GP_OT_copy_collision,
    GP_OT_select_collision,
    GP_OT_collision_display,
    GP_OT_rename_textures,
    GP_OT_install_import_script,
    GP_OT_validate,
    GP_OT_export_all,
    GP_OT_export_active,
    GP_OT_open_folder,
)


def register():
    for cls in CLASSES:
        bpy.utils.register_class(cls)


def unregister():
    for cls in reversed(CLASSES):
        bpy.utils.unregister_class(cls)
