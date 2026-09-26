"""Collision authoring without touching object names.

Godot's stock importer only understands name suffixes, which turns the outliner
into "Chair-col / Chair-convcolonly" soup and caps what you can express (no
margin, no layers, no primitives).  This module stores the same intent as
*custom properties* instead, so the data rides along in glTF `extras` and lands
in `node.get_meta("extras")` on the Godot side.

That means it needs a partner: godot/collision_post_import.gd, an
EditorScenePostImport script that reads the metadata back and builds the real
CollisionObject3D / CollisionShape3D nodes.  Metadata alone does nothing.

Primitive shapes are authored as real, correctly sized meshes parented to the
object they belong to.  Building the geometry at its true size (rather than
scaling a unit cube) keeps every proxy at scale 1, which is what keeps Godot
from complaining about non-uniform scale on collision nodes.
"""

import math

import bmesh
import bpy
from bpy.props import (
    BoolProperty, BoolVectorProperty, EnumProperty, FloatProperty, StringProperty,
)
from bpy.types import PropertyGroup
from mathutils import Matrix, Vector

# -- vocabulary -------------------------------------------------------------

BODY_ITEMS = [
    ('NONE', "None", "No physics body. Use this on collision shapes themselves", 0),
    ('STATIC', "StaticBody3D", "Immovable body. Walls, floors, furniture", 1),
    ('ANIMATABLE', "AnimatableBody3D", "StaticBody3D that pushes other bodies when moved by "
                                       "animation or code. Doors, platforms, elevators", 2),
    ('RIGID', "RigidBody3D", "Simulated by the physics engine. Debris, barrels, props", 3),
    ('CHARACTER', "CharacterBody3D", "Moved by code with move_and_slide. Players, monsters", 4),
    ('AREA', "Area3D", "Detects overlaps and applies no collision response. Triggers, pickups", 5),
    ('VEHICLE', "VehicleBody3D", "Arcade vehicle body", 6),
    ('PHYSICAL_BONE', "PhysicalBone3D", "One ragdoll bone. Lands under the skeleton's "
                                        "PhysicalBoneSimulator3D rather than in place, and drives "
                                        "the bone it names", 7),
]

BODY_NODE = {
    'NONE': "",
    'STATIC': "StaticBody3D",
    'ANIMATABLE': "AnimatableBody3D",
    'RIGID': "RigidBody3D",
    'CHARACTER': "CharacterBody3D",
    'AREA': "Area3D",
    'VEHICLE': "VehicleBody3D",
    'PHYSICAL_BONE': "PhysicalBone3D",
}

# PhysicalBone3D.joint_type, by name rather than by number: the number would be
# unreadable in the Custom Properties panel, and the import script maps it back.
JOINT_ITEMS = [
    ('NONE', "None", "No joint. The bone simulates free of its parent — rarely what you want "
                     "for a ragdoll, but right for a single detachable part", 0),
    ('PIN', "Pin", "Ball joint with no limits. What Godot's own «create physical skeleton» "
                   "produces", 1),
    ('CONE', "Cone Twist", "Ball joint with a swing/twist limit. The usual ragdoll choice for "
                           "limbs and neck", 2),
    ('HINGE', "Hinge", "One rotation axis. Knees and elbows", 3),
    ('SLIDER', "Slider", "One translation axis", 4),
    ('SIXDOF', "6DOF", "Every axis configurable by hand in Godot", 5),
]

# The string that reaches Godot; "6DOF" cannot be a Blender enum identifier.
JOINT_NAME = {
    'NONE': "NONE",
    'PIN': "PIN",
    'CONE': "CONE",
    'HINGE': "HINGE",
    'SLIDER': "SLIDER",
    'SIXDOF': "6DOF",
}

SHAPE_ITEMS = [
    ('NONE', "None", "No collision shape", 0),
    ('BOX', "Box", "BoxShape3D. Cheapest, use it whenever it fits", 1),
    ('SPHERE', "Sphere", "SphereShape3D. The fastest shape to test against", 2),
    ('CAPSULE', "Capsule", "CapsuleShape3D, standing along Z in Blender (Y in Godot). "
                           "The usual choice for characters", 3),
    ('CYLINDER', "Cylinder", "CylinderShape3D, standing along Z in Blender (Y in Godot)", 4),
    ('CONVEX', "Simple (Convex)", "ConvexPolygonShape3D built from the mesh hull. "
                                  "Works on moving bodies", 5),
    ('CONCAVE', "Trimesh (Concave)", "ConcavePolygonShape3D built from the exact mesh. "
                                     "Slowest, and only valid on static bodies", 6),
]

SHAPE_NODE = {
    'NONE': "",
    'BOX': "BoxShape3D",
    'SPHERE': "SphereShape3D",
    'CAPSULE': "CapsuleShape3D",
    'CYLINDER': "CylinderShape3D",
    'CONVEX': "ConvexPolygonShape3D",
    'CONCAVE': "ConcavePolygonShape3D",
}

PRIMITIVE_SHAPES = {'BOX', 'SPHERE', 'CAPSULE', 'CYLINDER'}
MESH_SHAPES = {'CONVEX', 'CONCAVE'}

# Shapes the physics engine refuses to move.  ConcavePolygonShape3D is only
# valid on StaticBody3D / AnimatableBody3D and on Area3D.
STATIC_ONLY_SHAPES = {'CONCAVE'}
MOVING_BODIES = {'RIGID', 'CHARACTER', 'VEHICLE', 'PHYSICAL_BONE'}

# Bodies that carry a mass.  PhysicalBone3D is a simulated body like RigidBody3D,
# so its mass matters just as much.
MASSIVE_BODIES = {'RIGID', 'PHYSICAL_BONE'}

# -- custom property keys ---------------------------------------------------
#
# These names are the contract with collision_post_import.gd.  Changing one
# means changing it there too.

KEY_BODY = "godot_body"
KEY_SHAPE = "godot_shape"
KEY_MARGIN = "godot_shape_margin"
KEY_VISUAL = "godot_shape_visual"
KEY_LAYER = "godot_collision_layer"
KEY_MASK = "godot_collision_mask"
KEY_MASS = "godot_mass"
KEY_PRIORITY = "godot_collision_priority"
KEY_BONE = "godot_bone"
KEY_JOINT = "godot_joint_type"

ALL_KEYS = (KEY_BODY, KEY_SHAPE, KEY_MARGIN, KEY_VISUAL,
            KEY_LAYER, KEY_MASK, KEY_MASS, KEY_PRIORITY,
            KEY_BONE, KEY_JOINT)

PROXY_PREFIX = "CO"

DISPLAY_COLOR = (0.16, 0.62, 1.0, 0.35)


# -- custom property mirroring ----------------------------------------------

def _bits_to_int(flags) -> int:
    value = 0
    for index, enabled in enumerate(flags):
        if enabled:
            value |= 1 << index
    return value


def armature_of(obj, depth=8):
    """The armature this object is rigged or parented to, or None."""
    if obj is None or depth <= 0:
        return None
    if obj.type == 'ARMATURE':
        return obj
    if obj.parent is not None and obj.parent.type == 'ARMATURE':
        return obj.parent
    for modifier in getattr(obj, "modifiers", []):
        if modifier.type == 'ARMATURE' and modifier.object is not None:
            return modifier.object
    return armature_of(obj.parent, depth - 1)


def bone_of(obj, depth=8) -> str:
    """Bone a PhysicalBone3D should drive.

    Bone parenting is the primary source: Blender's glTF exporter turns a
    bone-parented object into a child of that joint, Godot rebuilds it as a
    BoneAttachment3D, and the shape then sits where the artist put it without
    anyone typing a bone name.  The explicit field is the override for the cases
    that parenting cannot express — a shape that has to follow a different bone,
    or one that is not parented at all.
    """
    if obj is None or depth <= 0:
        return ""
    settings = getattr(obj, "godot_physics", None)
    if settings is not None and settings.bone:
        return settings.bone
    if obj.parent is not None and obj.parent_type == 'BONE' and obj.parent_bone:
        return obj.parent_bone
    # A proxy inherits the bone of the object it was built for.
    return bone_of(obj.parent, depth - 1)


def write_custom_props(obj):
    """Mirror the settings onto the object as real custom properties.

    They are written eagerly, on every change, so what the Object Properties >
    Custom Properties panel shows is exactly what the exporter will ship.
    """
    for key in ALL_KEYS:
        if key in obj:
            del obj[key]

    settings = obj.godot_physics
    body = BODY_NODE[settings.body]
    shape = SHAPE_NODE[settings.shape]
    if not body and not shape:
        return

    if body:
        obj[KEY_BODY] = body
        obj[KEY_LAYER] = _bits_to_int(settings.collision_layer)
        obj[KEY_MASK] = _bits_to_int(settings.collision_mask)
        if abs(settings.priority - 1.0) > 1e-6:
            obj[KEY_PRIORITY] = round(settings.priority, 6)
        if settings.body in MASSIVE_BODIES:
            obj[KEY_MASS] = round(settings.mass, 6)
        if settings.body == 'PHYSICAL_BONE':
            # An empty bone name is left out on purpose: the import script then
            # reports which object it could not place, instead of silently
            # attaching a ragdoll bone to whatever came first.
            bone = bone_of(obj)
            if bone:
                obj[KEY_BONE] = bone
            obj[KEY_JOINT] = JOINT_NAME[settings.joint_type]

    if shape:
        obj[KEY_SHAPE] = shape
        obj[KEY_MARGIN] = round(settings.margin, 6)
        # A node that is both a body and a shape source keeps its mesh; a bare
        # proxy is deleted by the import script once the shape is built.
        #
        # PhysicalBone3D is the exception, and it is not a corner case: what
        # gets tagged there is a collision blank sitting on a bone, while the
        # visible geometry is the skinned mesh somewhere else entirely. Keeping
        # its mesh would leave a stray box floating inside the character.
        keeps_mesh = settings.keep_mesh or (body and settings.body != 'PHYSICAL_BONE')
        if keeps_mesh:
            obj[KEY_VISUAL] = True


def clear_custom_props(obj):
    for key in ALL_KEYS:
        if key in obj:
            del obj[key]


def _sync(self, context):
    obj = self.id_data
    if isinstance(obj, bpy.types.Object):
        write_custom_props(obj)


# -- properties -------------------------------------------------------------

class GP_PhysicsSettings(PropertyGroup):
    body: EnumProperty(
        name="Body", items=BODY_ITEMS, default='NONE', update=_sync,
        description="Physics body this object becomes in Godot. Its collision shape children "
                    "are re-parented under it on import")
    shape: EnumProperty(
        name="Collision", items=SHAPE_ITEMS, default='NONE', update=_sync,
        description="Collision shape this object provides")
    margin: FloatProperty(
        name="Margin", default=0.04, min=0.0, max=1.0, step=1, precision=4, update=_sync,
        description="Shape3D.margin. Used by Jolt Physics, which is the default for projects "
                    "created in Godot 4.6 and later. GodotPhysics3D ignores it")
    keep_mesh: BoolProperty(
        name="Keep Mesh", default=False, update=_sync,
        description="Keep this object's mesh visible in Godot instead of replacing it with the "
                    "collision shape. Implied when the object also has a body")
    mass: FloatProperty(
        name="Mass", default=1.0, min=0.0001, soft_max=1000.0, update=_sync,
        description="Mass of the simulated body (RigidBody3D, PhysicalBone3D)")
    bone: StringProperty(
        name="Bone", default="", update=_sync,
        description="Bone this PhysicalBone3D drives. Leave empty to take it from the object's "
                    "bone parenting, which is the usual way")
    joint_type: EnumProperty(
        name="Joint", items=JOINT_ITEMS, default='CONE', update=_sync,
        description="How this ragdoll bone is tied to its parent bone")
    priority: FloatProperty(
        name="Priority", default=1.0, update=_sync,
        description="CollisionObject3D.collision_priority")
    collision_layer: BoolVectorProperty(
        name="Layer", size=32, subtype='LAYER', update=_sync,
        default=[True] + [False] * 31,
        description="Layers this body lives on")
    collision_mask: BoolVectorProperty(
        name="Mask", size=32, subtype='LAYER', update=_sync,
        default=[True] + [False] * 31,
        description="Layers this body scans")

    is_proxy: BoolProperty(
        name="Collision Proxy", default=False,
        description="Generated collision geometry rather than authored art")
    display: StringProperty(default="")   # remembers the display mode applied


def is_proxy(obj) -> bool:
    return bool(getattr(obj, "godot_physics", None)) and obj.godot_physics.is_proxy


def has_physics(obj) -> bool:
    settings = getattr(obj, "godot_physics", None)
    return bool(settings) and (settings.body != 'NONE' or settings.shape != 'NONE')


def iter_proxies(objects):
    return [obj for obj in objects if is_proxy(obj)]


# -- geometry ---------------------------------------------------------------

def local_bounds(obj):
    """(center, size) of the object's local bounding box, never degenerate."""
    corners = [Vector(corner) for corner in obj.bound_box]
    if not corners:
        return Vector((0.0, 0.0, 0.0)), Vector((1.0, 1.0, 1.0))
    low = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
    high = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
    size = high - low
    # A flat object still needs a shape with volume.
    size = Vector((max(size.x, 1e-3), max(size.y, 1e-3), max(size.z, 1e-3)))
    return (low + high) * 0.5, size


def _lathe(profile, segments):
    """Revolve a (radius, z) silhouette around Z.

    Profile points run bottom to top.  A zero radius at either end becomes a
    pole; a non-zero radius becomes a flat cap.  One routine covers spheres,
    cylinders and capsules.
    """
    verts = []
    faces = []
    rings = []

    for radius, z in profile:
        if radius <= 1e-9:
            rings.append([len(verts)])
            verts.append((0.0, 0.0, z))
            continue
        ring = []
        for index in range(segments):
            angle = 2.0 * math.pi * index / segments
            ring.append(len(verts))
            verts.append((radius * math.cos(angle), radius * math.sin(angle), z))
        rings.append(ring)

    for lower, upper in zip(rings, rings[1:]):
        if len(lower) == 1:                       # bottom pole
            apex = lower[0]
            for index in range(len(upper)):
                nxt = (index + 1) % len(upper)
                faces.append((apex, upper[nxt], upper[index]))
        elif len(upper) == 1:                     # top pole
            apex = upper[0]
            for index in range(len(lower)):
                nxt = (index + 1) % len(lower)
                faces.append((apex, lower[index], lower[nxt]))
        else:
            for index in range(len(lower)):
                nxt = (index + 1) % len(lower)
                faces.append((lower[index], lower[nxt], upper[nxt], upper[index]))

    if len(rings[0]) > 1:                          # flat bottom cap
        faces.append(tuple(reversed(rings[0])))
    if len(rings[-1]) > 1:                         # flat top cap
        faces.append(tuple(rings[-1]))

    return verts, faces


def _box_geometry(size):
    half = size * 0.5
    verts = [(sx * half.x, sy * half.y, sz * half.z)
             for sx, sy, sz in ((-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1),
                                (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1))]
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4),
             (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return verts, faces


def _sphere_geometry(radius, segments, rings=8):
    profile = []
    for index in range(rings + 1):
        angle = -math.pi / 2.0 + math.pi * index / rings
        profile.append((radius * math.cos(angle), radius * math.sin(angle)))
    return _lathe(profile, segments)


def _cylinder_geometry(radius, height, segments):
    half = height * 0.5
    return _lathe([(radius, -half), (radius, half)], segments)


def _capsule_geometry(radius, total_height, segments, rings=4):
    """Godot's CapsuleShape3D height is the total height, caps included."""
    cylinder = max(total_height - 2.0 * radius, 0.0)
    half = cylinder * 0.5
    profile = []
    for index in range(rings + 1):                 # bottom hemisphere
        angle = -math.pi / 2.0 + (math.pi / 2.0) * index / rings
        profile.append((radius * math.cos(angle), -half + radius * math.sin(angle)))
    for index in range(rings + 1):                 # top hemisphere
        angle = (math.pi / 2.0) * index / rings
        profile.append((radius * math.cos(angle), half + radius * math.sin(angle)))
    return _lathe(profile, segments)


def _hull_geometry(source_obj):
    """Convex hull of the source mesh, in the source's local space."""
    mesh = bpy.data.meshes.new_from_object(source_obj)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bpy.data.meshes.remove(mesh)
    result = bmesh.ops.convex_hull(bm, input=bm.verts, use_existing_faces=False)
    unused = result.get("geom_interior", []) + result.get("geom_unused", [])
    if unused:
        bmesh.ops.delete(bm, geom=unused, context='VERTS')
    verts = [tuple(vert.co) for vert in bm.verts]
    index = {vert: i for i, vert in enumerate(bm.verts)}
    faces = [tuple(index[vert] for vert in face.verts) for face in bm.faces]
    bm.free()
    return verts, faces


def _copy_geometry(source_obj):
    mesh = bpy.data.meshes.new_from_object(source_obj)
    verts = [tuple(vert.co) for vert in mesh.vertices]
    faces = [tuple(poly.vertices) for poly in mesh.polygons]
    bpy.data.meshes.remove(mesh)
    return verts, faces


def build_shape_mesh(name, shape, owner, segments=16):
    """Mesh datablock for `shape`, fitted to `owner`, plus its local offset."""
    center, size = local_bounds(owner)

    if shape == 'BOX':
        verts, faces = _box_geometry(size)
    elif shape == 'SPHERE':
        verts, faces = _sphere_geometry(max(size) * 0.5, segments)
    elif shape == 'CAPSULE':
        radius = max(size.x, size.y) * 0.5
        verts, faces = _capsule_geometry(radius, max(size.z, 2.0 * radius), segments)
    elif shape == 'CYLINDER':
        verts, faces = _cylinder_geometry(max(size.x, size.y) * 0.5, size.z, segments)
    elif shape == 'CONVEX':
        verts, faces = _hull_geometry(owner)
        center = Vector((0.0, 0.0, 0.0))
    elif shape == 'CONCAVE':
        verts, faces = _copy_geometry(owner)
        center = Vector((0.0, 0.0, 0.0))
    else:
        return None, Vector((0.0, 0.0, 0.0))

    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.validate()
    mesh.update()
    return mesh, center


def proxy_name(owner, shape) -> str:
    """A name Godot's own suffix reader will not mistake for an import hint.

    "Chair_col" would be read as a collision suffix by the stock importer, so
    the shape word goes in the middle and the name is prefixed instead.
    """
    return "%s_%s_%s" % (PROXY_PREFIX, owner.name, shape.capitalize())


def create_proxy(owner, shape, margin=0.04, segments=16):
    """Create a collision proxy object parented to `owner`. Returns the object."""
    mesh, center = build_shape_mesh(proxy_name(owner, shape), shape, owner, segments)
    if mesh is None:
        return None

    proxy = bpy.data.objects.new(proxy_name(owner, shape), mesh)
    for collection in owner.users_collection:
        collection.objects.link(proxy)

    proxy.parent = owner
    proxy.matrix_parent_inverse = Matrix.Identity(4)
    proxy.location = center
    proxy.rotation_euler = (0.0, 0.0, 0.0)
    proxy.scale = (1.0, 1.0, 1.0)

    proxy.godot_physics.is_proxy = True
    proxy.godot_physics.shape = shape
    proxy.godot_physics.margin = margin
    proxy.hide_render = True
    apply_display(proxy, 'WIRE')
    write_custom_props(proxy)
    return proxy


def refit_proxy(proxy, segments=16) -> bool:
    """Rebuild a proxy's geometry against its parent's current bounds."""
    owner = proxy.parent
    shape = proxy.godot_physics.shape
    if owner is None or shape == 'NONE':
        return False
    mesh, center = build_shape_mesh(proxy.data.name, shape, owner, segments)
    if mesh is None:
        return False
    old = proxy.data
    proxy.data = mesh
    if old.users == 0:
        bpy.data.meshes.remove(old)
    proxy.location = center
    proxy.rotation_euler = (0.0, 0.0, 0.0)
    proxy.scale = (1.0, 1.0, 1.0)
    return True


# -- viewport display -------------------------------------------------------

DISPLAY_ITEMS = [
    ('WIRE', "Wire", "Wireframe drawn in front of the mesh. Readable in any shading mode"),
    ('SOLID', "Solid", "Solid blue. Pair it with viewport X-Ray (Alt+Z) for the translucent look"),
    ('BOUNDS', "Bounds", "Bounding box only, the lightest option for heavy scenes"),
    ('HIDE', "Hidden", "Hide collision proxies in the viewport"),
]


# Имя служебного материала подсветки прокси. Он живёт только во вьюпорте Blender,
# но прокси экспортируются вместе с ним, поэтому экспорт обязан знать его в лицо:
# иначе он заводит ему .tres и ссылки use_external, как настоящему материалу.
PREVIEW_MATERIAL = "GP_CollisionPreview"


def preview_material():
    """Shared viewport-display material, so proxies read as one thing."""
    material = bpy.data.materials.get(PREVIEW_MATERIAL)
    if material is None:
        material = bpy.data.materials.new(PREVIEW_MATERIAL)
        material.use_fake_user = True
    material.diffuse_color = DISPLAY_COLOR
    material.roughness = 1.0
    return material


def apply_display(obj, mode):
    obj.color = DISPLAY_COLOR
    obj.hide_render = True
    obj.display.show_shadows = False
    obj.godot_physics.display = mode

    # hide_viewport is the datablock-level switch, so it works headlessly and
    # regardless of which view layer the object happens to be in.
    obj.hide_viewport = (mode == 'HIDE')
    if mode == 'HIDE':
        return

    if mode == 'WIRE':
        obj.display_type = 'WIRE'
        obj.show_in_front = True
    elif mode == 'BOUNDS':
        obj.display_type = 'BOUNDS'
        obj.show_in_front = False
    else:
        obj.display_type = 'SOLID'
        obj.show_in_front = False
        material = preview_material()
        if obj.data is not None and not obj.data.materials:
            obj.data.materials.append(material)
        elif obj.data is not None:
            obj.data.materials[0] = material


CLASSES = (GP_PhysicsSettings,)


def register():
    for cls in CLASSES:
        bpy.utils.register_class(cls)
    bpy.types.Object.godot_physics = bpy.props.PointerProperty(type=GP_PhysicsSettings)


def unregister():
    del bpy.types.Object.godot_physics
    for cls in reversed(CLASSES):
        bpy.utils.unregister_class(cls)
