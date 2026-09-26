"""Godot Pipeline: per-collection glTF asset delivery from Blender to Godot 4.

Design in one paragraph: a Godot .glb is an *independent unit*, so one Blender
collection becomes one .glb, in its own folder, with its own .import file whose
settings the add-on owns.  Materials and textures are kept out of the .glb by
default so that re-exporting geometry can never overwrite material work done in
the engine.

Headless use (CI, batch re-export of many .blend files):

    blender --background monsters.blend --python-expr \
        "import godot_pipeline; godot_pipeline.export_all_headless()"

Requires the add-on to be enabled in the Blender user preferences the headless
run inherits.
"""

import bpy

# bl_info is redundant next to blender_manifest.toml, but keeps the package
# installable as a legacy add-on on builds where extensions are unavailable.
bl_info = {
    "name": "Godot Pipeline",
    "author": "Yanislav Pichugin <yanislavpic@gmail.com>",
    "version": (1, 4, 0),
    "blender": (4, 2, 0),
    "location": "3D View > Sidebar > Godot, Properties > Collection/Object/Material",
    "description": "Per-collection glTF asset delivery pipeline for Godot 4",
    "category": "Import-Export",
}

from . import props, physics, prefs, ops, ui   # noqa: E402  (must follow bl_info)

MODULES = (props, physics, prefs, ops, ui)

# layers.py and ucupaint.py hold no Blender types, so they register nothing and
# are imported where they are used.


def register():
    for module in MODULES:
        module.register()


def unregister():
    for module in reversed(MODULES):
        module.unregister()


# -- headless entry points --------------------------------------------------

def export_all_headless(project_root: str = "") -> int:
    """Export every marked collection of the current .blend.

    Returns the number of failed assets so a CI step can use it as an exit code.
    """
    from . import exporter
    from .prefs import get_prefs

    context = bpy.context
    addon_prefs = get_prefs(context)
    if project_root:
        addon_prefs.godot_project = project_root

    collections = exporter.collect_assets(context.scene)
    results, fatal = exporter.export_many(context, addon_prefs, collections)
    if fatal:
        print("[godot_pipeline] FATAL: " + fatal)
        return 1

    for result in results:
        print("[godot_pipeline] %-9s %-28s %s"
              % (result.status, result.collection.name, result.path))
        for message in result.messages:
            print("[godot_pipeline]           - %s" % message)
    print("[godot_pipeline] " + exporter.format_report(results))
    return sum(1 for r in results if r.status == "failed")


def validate_headless(project_root: str = "") -> int:
    """Validate without exporting. Returns the number of blocking errors."""
    from . import exporter, validate as validate_mod
    from .prefs import get_prefs

    context = bpy.context
    addon_prefs = get_prefs(context)
    if project_root:
        addon_prefs.godot_project = project_root

    collections = exporter.collect_assets(context.scene)
    issues = validate_mod.validate(context, addon_prefs, collections)
    for issue in issues:
        print("[godot_pipeline] %s %s: %s" % (issue.level, issue.asset or "-", issue.message))
    return sum(1 for i in issues if i.level == validate_mod.ERROR)
