"""Reading and patching Godot .import files, and generating external material stubs.

The .import file is the only place where "this .glb must not spill textures into
my project" can be recorded, and Godot rewrites it on every reimport while
preserving unknown keys.  So the pipeline patches the keys it owns and leaves
everything else, including Godot's uid/path bookkeeping, untouched.

Format reference (Godot 4.x, editor/import/3d/resource_importer_scene.cpp):
    importer="scene", importer_version=1, type="PackedScene", save extension .scn
"""

import json
import os
import re

# Godot's GLTFState::HandleBinaryImageMode
EMBEDDED_IMAGE_DISCARD = 0
EMBEDDED_IMAGE_EXTRACT = 1
EMBEDDED_IMAGE_BASISU = 2
EMBEDDED_IMAGE_UNCOMPRESSED = 3

_KEY_RE = re.compile(r'^([A-Za-z_][\w/.]*)\s*=\s*(.*)$')


def _balanced(text: str) -> bool:
    """True when every { [ ( in `text` is closed. Quote-aware, which is enough
    for the value literals Godot writes."""
    depth = 0
    in_string = False
    escape = False
    for char in text:
        if escape:
            escape = False
            continue
        if char == '\\':
            escape = True
            continue
        if char == '"':
            in_string = not in_string
            continue
        if in_string:
            continue
        if char in '{[(':
            depth += 1
        elif char in '}])':
            depth -= 1
    return depth <= 0


class ImportFile:
    """A minimally invasive .import reader/writer.

    Sections keep their original order and every value is stored as its raw
    text, so keys the add-on does not understand survive a round trip byte for
    byte.
    """

    def __init__(self):
        self.order = []               # section names in file order
        self.sections = {}            # name -> list of [key, raw_value]
        self.exists = False

    # -- io ------------------------------------------------------------------

    @classmethod
    def load(cls, path: str) -> "ImportFile":
        obj = cls()
        if not os.path.isfile(path):
            return obj
        with open(path, "r", encoding="utf-8") as handle:
            obj._parse(handle.read())
        obj.exists = True
        return obj

    @classmethod
    def from_text(cls, text: str) -> "ImportFile":
        obj = cls()
        obj._parse(text)
        return obj

    def _parse(self, text: str):
        section = None
        pending_key = None
        pending_value = []
        for line in text.splitlines():
            if pending_key is not None:
                pending_value.append(line)
                joined = "\n".join(pending_value)
                if _balanced(joined):
                    self._append(section, pending_key, joined)
                    pending_key, pending_value = None, []
                continue

            stripped = line.strip()
            if stripped.startswith("[") and stripped.endswith("]"):
                section = stripped[1:-1]
                if section not in self.sections:
                    self.order.append(section)
                    self.sections[section] = []
                continue
            if not stripped or stripped.startswith(";"):
                continue
            match = _KEY_RE.match(stripped)
            if not match:
                continue
            key, value = match.group(1), match.group(2)
            if _balanced(value):
                self._append(section, key, value)
            else:
                pending_key, pending_value = key, [value]
        if pending_key is not None:      # truncated file, keep what we have
            self._append(section, pending_key, "\n".join(pending_value))

    def _append(self, section, key, value):
        if section is None:
            section = "remap"
        if section not in self.sections:
            self.order.append(section)
            self.sections[section] = []
        self.sections[section].append([key, value])

    def dumps(self) -> str:
        chunks = []
        for name in self.order:
            chunks.append("[%s]\n" % name)
            for key, value in self.sections[name]:
                chunks.append("%s=%s" % (key, value))
            chunks.append("")
        return "\n".join(chunks).rstrip("\n") + "\n"

    def save(self, path: str):
        with open(path, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(self.dumps())

    # -- accessors -----------------------------------------------------------

    def get(self, section: str, key: str, default=None):
        for existing_key, value in self.sections.get(section, []):
            if existing_key == key:
                return value
        return default

    def set(self, section: str, key: str, value: str) -> bool:
        """Set a raw value. Returns True when the file actually changed."""
        if section not in self.sections:
            self.order.append(section)
            self.sections[section] = []
        for entry in self.sections[section]:
            if entry[0] == key:
                if entry[1] == value:
                    return False
                entry[1] = value
                return True
        self.sections[section].append([key, value])
        return True


# -- Godot literal helpers --------------------------------------------------

def lit(value) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, float):
        return repr(round(value, 6))
    return str(value)


def new_import_text(res_source: str) -> str:
    """A minimal but valid .import for a scene.

    uid, path and dest_files are deliberately omitted: Godot fills them in on
    the next scan, and guessing them would produce a stale cache entry.
    """
    return (
        "[remap]\n\n"
        'importer="scene"\n'
        "importer_version=1\n"
        'type="PackedScene"\n'
        "\n[deps]\n\n"
        'source_file="%s"\n'
        "\n[params]\n\n" % res_source
    )


def scene_params(profile, material_policy: str) -> dict:
    """The [params] keys this add-on owns, as {key: python value}."""
    from .props import LIGHT_BAKE_VALUE, PHYSICS_ROOT_TYPE

    embedded = {
        'EXTERNAL': EMBEDDED_IMAGE_DISCARD,
        'EXTRACT': EMBEDDED_IMAGE_EXTRACT,
        'EMBED': EMBEDDED_IMAGE_UNCOMPRESSED,
    }[material_policy]

    params = {
        "nodes/root_type": PHYSICS_ROOT_TYPE[profile.root_type],
        "nodes/apply_root_scale": True,
        "nodes/root_scale": float(profile.root_scale),
        "nodes/use_name_suffixes": True,
        "nodes/use_node_type_suffixes": True,
        "meshes/ensure_tangents": bool(profile.ensure_tangents),
        "meshes/generate_lods": bool(profile.generate_lods),
        "meshes/create_shadow_meshes": bool(profile.create_shadow_meshes),
        "meshes/light_baking": LIGHT_BAKE_VALUE[profile.light_bake_mode],
        "animation/import": bool(profile.import_animations),
        "animation/fps": int(profile.animation_fps),
        # The key that stops Godot from re-spilling textures into the project.
        "gltf/embedded_image_handling": embedded,
    }
    if profile.import_script:
        params["import_script/path"] = profile.import_script
    return params


def _load_subresources(import_file: "ImportFile"):
    """Parse _subresources. Godot writes it as valid JSON, but bail out rather
    than mangle anything exotic."""
    raw = import_file.get("params", "_subresources")
    if raw is None or raw.strip() in ("{}", ""):
        return {}, True
    try:
        return json.loads(raw), True
    except ValueError:
        return {}, False


def _dump_subresources(data: dict) -> str:
    return json.dumps(data, indent=0, ensure_ascii=False).replace(": ", ":")


def apply_material_links(import_file: "ImportFile", material_links: dict):
    """Point named materials at external .tres resources.

    `material_links` maps the material name as exported into the glTF to a
    res:// path.  Returns (changed, warning).
    """
    if not material_links:
        return False, ""

    subresources, parsed = _load_subresources(import_file)
    if not parsed:
        return False, "_subresources is hand-edited, material links left alone"

    materials = subresources.setdefault("materials", {})
    changed = False
    for name, res_path in material_links.items():
        entry = materials.setdefault(name, {})
        if entry.get("use_external/enabled") is not True:
            entry["use_external/enabled"] = True
            changed = True
        # Godot rewrites this into a uid:// on the next import; a res:// path is
        # accepted as input and is what survives review in a diff.
        if entry.get("use_external/fallback_path") != res_path:
            entry["use_external/fallback_path"] = res_path
            changed = True
        if not str(entry.get("use_external/path", "")).startswith("uid://"):
            if entry.get("use_external/path") != res_path:
                entry["use_external/path"] = res_path
                changed = True

    if changed:
        import_file.set("params", "_subresources", _dump_subresources(subresources))
    return changed, ""


def write_import_settings(glb_abs: str, res_source: str, profile, material_policy: str,
                          material_links: dict, create_if_missing: bool):
    """Patch (or create) <glb>.import. Returns (status, changed_keys, warning)."""
    import_path = glb_abs + ".import"
    import_file = ImportFile.load(import_path)
    existed = import_file.exists

    if not existed:
        if not create_if_missing:
            return "missing", [], (
                "%s.import does not exist yet. Open the Godot editor once so it is "
                "generated, then export again (or enable 'Create .import If Missing')"
                % os.path.basename(glb_abs))
        import_file = ImportFile.from_text(new_import_text(res_source))

    changed = []
    for key, value in scene_params(profile, material_policy).items():
        if import_file.set("params", key, lit(value)):
            changed.append(key)

    warning = ""
    if profile.link_external_materials:
        mat_changed, warning = apply_material_links(import_file, material_links)
        if mat_changed:
            changed.append("_subresources")

    if not existed or changed:
        import_file.save(import_path)
        return ("patched" if existed else "created"), changed, warning
    return "unchanged", [], warning


MATERIAL_STUB = (
    '[gd_resource type="StandardMaterial3D" format=3]\n'
    "\n"
    "[resource]\n"
    'resource_name = "%s"\n'
)


def ensure_material_stub(abs_path: str, material_name: str) -> bool:
    """Create an empty StandardMaterial3D .tres if it is not there yet.

    Never overwrites: the whole point of an external material is that Godot is
    its owner.
    """
    if os.path.isfile(abs_path):
        return False
    os.makedirs(os.path.dirname(abs_path), exist_ok=True)
    with open(abs_path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(MATERIAL_STUB % material_name)
    return True
