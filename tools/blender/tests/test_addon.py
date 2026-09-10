"""Проверки плагина godot_pipeline: имена карт, слои, коллизии, PhysicalBone3D.

Запускать не напрямую, а раннером: он готовит временную папку скриптов Blender
и временный проект Godot, иначе тест писал бы в реальный проект.

    pwsh tools/blender/tests/run_addon_tests.ps1

Blender-половина. Godot-половина — verify_ragdoll.gd рядом: она разбирает уже
импортированную сцену и проверяет, что из метаданных собрались настоящие узлы.
"""

import inspect
import os
import re
import sys

import bpy

# Готовит раннер: временный проект под экспорт и настоящий — под чтение
# [layer_names]. Разделены намеренно, тест ничего не пишет в репозиторий.
OUT = os.environ["GP_TEST_PROJECT"]
REAL = os.environ["GP_REAL_PROJECT"]

failures = []


def check(condition, label):
    print(("PASS  " if condition else "FAIL  ") + label)
    if not condition:
        failures.append(label)


bpy.ops.preferences.addon_enable(module="godot_pipeline")
import godot_pipeline                                          # noqa: E402
from godot_pipeline import layers, physics, ucupaint            # noqa: E402
from godot_pipeline import validate as validate_mod            # noqa: E402
from godot_pipeline.exporter import collect_assets             # noqa: E402
from godot_pipeline.prefs import get_prefs                     # noqa: E402


# -- 1. имена карт ----------------------------------------------------------

print("\n=== 1. имена карт (Ucupaint -> конвенция) ===")
CASES = [
    ("MAT_door Color", "T_door_albedo"),
    ("MAT_door Normal", "T_door_n"),
    ("MAT_door_ORM", "T_door_orm"),
    ("MAT_door Ambient Occlusion", "T_door_ao"),
    ("MAT_door Roughness", "T_door_roughness"),
    ("MAT_door Metallic", "T_door_metallic"),
    ("MAT_door Displacement", "T_door_height"),
    ("MAT_door Emission", "T_door_emission"),
    ("MAT_room_base Base Color", "T_room_base_albedo"),
    ("hero_skin normal", "T_hero_skin_n"),
]
for source, expected in CASES:
    got = ucupaint.target_name(source)
    check(got == expected, "%-34s -> %-22s (получено %r)" % (source, expected, got))

print("--- слова, которые НЕ должны считаться каналом ---")
# Shield_arm ловил алиас ARM для ORM, пока тот не был выкинут: в проекте с
# риггингом «_arm» — часть тела куда чаще, чем карта.
for source in ("Armor", "Colorful", "Shield_arm", "upper_arm", "MAT_door"):
    got = ucupaint.target_name(source)
    check(got == "", "%-20s не распознан как карта (получено %r)" % (source, got))

plans, skipped = ucupaint.plan_renames([], "", False)
check(plans == [] and skipped == [], "пустой список не падает")


# -- 2. имена слоёв ---------------------------------------------------------

print("\n=== 2. имена слоёв из project.godot ===")
# Временный проект: содержимое известно точно, включая дырку в нумерации.
temp = layers.physics_layers(OUT)
check(temp[0] == "static_colliders", "слой 1 (получено %r)" % temp[0])
check(temp[1] == "player", "слой 2 (получено %r)" % temp[1])
check(temp[6] == "permeable", "слой 7 через дырку в нумерации (получено %r)" % temp[6])
check(temp[3] == "", "слой 4 не назван")
check(layers.named_indices(temp) == [0, 1, 2, 6], "названные слои: %s"
      % layers.named_indices(temp))
check(layers.label(temp, 3) == "Layer 4", "безымянный подписан номером")
check(layers.describe(temp, 1 | (1 << 6)) == "static_colliders, permeable",
      "маска расписывается именами: %r" % layers.describe(temp, 1 | (1 << 6)))
check(layers.physics_layers("") == [""] * 32, "без проекта — пустые имена, без падения")
check(layers.physics_layers(os.path.join(OUT, "нет-такой-папки")) == [""] * 32,
      "несуществующий путь не роняет разбор")

# Настоящий проект: сверяем с независимым разбором того же файла, а не с
# зашитыми именами — иначе тест ломался бы при первом переименовании слоя.
real = layers.physics_layers(REAL)
naive = {}
with open(os.path.join(REAL, "project.godot"), "r", encoding="utf-8") as handle:
    for line in handle:
        found = re.match(r'^3d_physics/layer_(\d+)="(.*)"\s*$', line.strip())
        if found:
            naive[int(found.group(1)) - 1] = found.group(2)
check(bool(naive), "в проекте вообще есть именованные слои (%d)" % len(naive))
check(all(real[index] == name for index, name in naive.items()),
      "разбор совпадает с независимым чтением файла")
check(len(layers.named_indices(real)) == len(naive),
      "лишних имён не выдумано (%d против %d)"
      % (len(layers.named_indices(real)), len(naive)))


# -- 3. only_changed убран --------------------------------------------------

print("\n=== 3. отбор «только изменённые» убран ===")
check(not hasattr(bpy.types.Scene, "godot_pipeline"),
      "Scene.godot_pipeline больше не регистрируется")
signature = inspect.signature(godot_pipeline.export_all_headless)
check("only_changed" not in signature.parameters, "export_all_headless без only_changed")


# -- 4. PhysicalBone3D ------------------------------------------------------

print("\n=== 4. PhysicalBone3D ===")
for obj in list(bpy.data.objects):
    bpy.data.objects.remove(obj, do_unlink=True)
for coll in list(bpy.data.collections):
    bpy.data.collections.remove(coll)

scene = bpy.context.scene
asset = bpy.data.collections.new("Ragdoll")
scene.collection.children.link(asset)

# Арматура с деформирующими костями и одной контрольной: последняя нужна, чтобы
# проверить ловушку с Export Deformation Bones Only.
bpy.ops.object.armature_add(enter_editmode=True)
armature = bpy.context.active_object
armature.name = "Rig"
edit = armature.data.edit_bones
edit[0].name = "spine"
edit[0].head = (0.0, 0.0, 0.0)
edit[0].tail = (0.0, 0.0, 1.0)
upper = edit.new("upper_arm")
upper.head = (0.0, 0.0, 1.0)
upper.tail = (0.0, 0.0, 2.0)
upper.parent = edit[0]
ctrl = edit.new("ctrl_ik")
ctrl.head = (1.0, 0.0, 1.0)
ctrl.tail = (1.0, 0.0, 2.0)
bpy.ops.object.mode_set(mode='OBJECT')
armature.data.bones["ctrl_ik"].use_deform = False

# Скиненный меш обязателен: без skin в glTF нет joints, а значит и Skeleton3D
# в Godot — и вешать PhysicalBone3D будет не на что.
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.0, 1.0))
body = bpy.context.active_object
body.name = "hero_body"
group = body.vertex_groups.new(name="spine")
group.add(range(len(body.data.vertices)), 1.0, 'REPLACE')
modifier = body.modifiers.new("Armature", 'ARMATURE')
modifier.object = armature
body.parent = armature

for obj in (armature, body):
    for coll in list(obj.users_collection):
        coll.objects.unlink(obj)
    asset.objects.link(obj)

bpy.ops.mesh.primitive_cube_add(size=0.5, location=(0.0, 0.0, 1.5))
shape = bpy.context.active_object
shape.name = "arm_shape"
for coll in list(shape.users_collection):
    coll.objects.unlink(shape)
asset.objects.link(shape)
shape.parent = armature
shape.parent_type = 'BONE'
shape.parent_bone = "upper_arm"
shape.matrix_parent_inverse = armature.matrix_world.inverted()

check(physics.armature_of(shape) is armature, "armature_of находит арматуру через привязку")
check(physics.bone_of(shape) == "upper_arm",
      "bone_of берёт кость из привязки (получено %r)" % physics.bone_of(shape))

shape.godot_physics.body = 'PHYSICAL_BONE'
shape.godot_physics.shape = 'CAPSULE'
shape.godot_physics.joint_type = 'CONE'
shape.godot_physics.mass = 3.5
shape.godot_physics.collision_layer[0] = False
shape.godot_physics.collision_layer[2] = True
physics.write_custom_props(shape)

check(shape[physics.KEY_BODY] == "PhysicalBone3D", "godot_body записан")
check(shape[physics.KEY_BONE] == "upper_arm",
      "godot_bone записан: %r" % shape.get(physics.KEY_BONE))
check(shape[physics.KEY_JOINT] == "CONE", "godot_joint_type записан")
check(abs(shape[physics.KEY_MASS] - 3.5) < 1e-6, "масса записана для PhysicalBone3D")
check(shape[physics.KEY_LAYER] == 4, "слой записан битом 3 (получено %s)" % shape[physics.KEY_LAYER])
# Болванка на кости — не визуал: визуал это скиненный меш в другом месте, и
# оставленный меш болванки болтался бы внутри персонажа.
check(physics.KEY_VISUAL not in shape, "прокси рэгдолла не помечен как визуал")

print("--- поле Bone перебивает привязку ---")
shape.godot_physics.bone = "spine"
physics.write_custom_props(shape)
check(shape[physics.KEY_BONE] == "spine", "явное поле выигрывает")
shape.godot_physics.bone = ""
physics.write_custom_props(shape)
check(shape[physics.KEY_BONE] == "upper_arm", "пустое поле возвращает привязку")


# -- 5. валидатор -----------------------------------------------------------

print("\n=== 5. валидатор ===")
prefs = get_prefs(bpy.context)
prefs.godot_project = OUT
asset.godot.is_asset = True
asset.godot.profile = "Character"
asset.godot.dest_dir = "assets"

found = validate_mod.validate(bpy.context, prefs, collect_assets(scene))
check("deform" not in " | ".join(i.message for i in found),
      "деформирующая кость претензий не вызывает")

shape.godot_physics.bone = "ctrl_ik"
physics.write_custom_props(shape)
found = validate_mod.validate(bpy.context, prefs, collect_assets(scene))
check("deform" in " | ".join(i.message for i in found),
      "контрольная кость при deform-only ловится ошибкой")

shape.godot_physics.bone = "нет-такой-кости"
physics.write_custom_props(shape)
found = validate_mod.validate(bpy.context, prefs, collect_assets(scene))
check(any("has no bone" in i.message for i in found), "несуществующая кость ловится")

shape.godot_physics.bone = ""
physics.write_custom_props(shape)


# -- 6. ренейминг файлов на диске -------------------------------------------

print("\n=== 6. ренейминг файлов на диске ===")
texture_dir = os.path.join(OUT, "src_textures")
os.makedirs(texture_dir, exist_ok=True)

for source_name in ("MAT_hero Color", "MAT_hero Normal", "MAT_hero_ORM"):
    image = bpy.data.images.new(source_name, 4, 4)
    image.filepath_raw = os.path.join(texture_dir, source_name + ".png")
    image.file_format = 'PNG'
    image.save()

bpy.ops.godot_pipeline.rename_textures(scope='ALL', rename_files=True)

for name in ("T_hero_albedo", "T_hero_n", "T_hero_orm"):
    check(name in bpy.data.images, "датаблок переименован: %s" % name)
    check(os.path.isfile(os.path.join(texture_dir, name + ".png")),
          "файл на диске переименован: %s.png" % name)

for old in ("MAT_hero Color.png", "MAT_hero Normal.png", "MAT_hero_ORM.png"):
    check(not os.path.isfile(os.path.join(texture_dir, old)), "старого файла нет: %s" % old)

renamed = bpy.data.images.get("T_hero_albedo")
check(renamed is not None
      and os.path.basename(bpy.path.abspath(renamed.filepath)) == "T_hero_albedo.png",
      "filepath датаблока переставлен на новый файл")

before = sorted(i.name for i in bpy.data.images)
try:
    bpy.ops.godot_pipeline.rename_textures(scope='ALL', rename_files=True)
except RuntimeError:
    pass                      # оператор докладывает CANCELLED, когда делать нечего
check(before == sorted(i.name for i in bpy.data.images), "идемпотентно: имена не изменились")

for image in list(bpy.data.images):
    if image.name.startswith("T_hero"):
        bpy.data.images.remove(image)


# -- 7. что уезжает в проект, а что остаётся в .blend ------------------------

print("")
print("=== 7. канонические карты и место материала ===")
from godot_pipeline import textures                              # noqa: E402
from godot_pipeline.exporter import material_dirs                # noqa: E402

for name in ("T_door_albedo.png", "T_door_n.png", "T_door_orm.png", "T_door_emission.png"):
    check(textures.classify(name) == "ship", "уезжает: %s" % name)

# Промежуточные: именно из них Ucupaint собирает ORM, но в игре они не нужны.
for name in ("T_door_ao.png", "T_door_roughness.png", "T_door_metallic.png",
             "T_door_height.png"):
    check(textures.classify(name) == "intermediate", "остаётся в .blend: %s" % name)

# Нераспознанное копируется, а не выбрасывается: ошибиться в эту сторону дешевле.
for name in ("palette_grid.png", "SM_Door.png"):
    check(textures.classify(name) == "unknown", "нераспознано, но копируется: %s" % name)

# Часть тела не должна прочитаться как ORM — тот самый Shield_arm.
check(textures.classify("T_Shield_arm.png") == "unknown", "_arm не читается как ORM")

# Односимвольный суффикс нормали держится только на правиле разделителя.
for name in ("Stone.png", "T_hero_skin.png", "T_door_sign.png"):
    check(textures.classify(name) == "unknown", "не путается с картой нормали: %s" % name)

profile = next(p for p in prefs.profiles if p.name == "Character")
profile.material_dir = "assets/materials"
profile.texture_dir = "assets/textures"
profile.subfolder_per_asset = True

shared_mat = bpy.data.materials.new("MAT_palette")
unique_mat = bpy.data.materials.new("MAT_door")
unique_mat.godot.location = 'ASSET'

check(material_dirs(profile, asset, shared_mat) == ("assets/materials", "assets/textures"),
      "общий материал -> общие папки (получено %s)"
      % (material_dirs(profile, asset, shared_mat),))
check(material_dirs(profile, asset, unique_mat)
      == ("assets/Ragdoll/materials", "assets/Ragdoll/textures"),
      "уникальный материал -> рядом с ассетом (получено %s)"
      % (material_dirs(profile, asset, unique_mat),))

# Текстуры обязаны ехать за своим материалом: иначе уникальная карта ляжет в
# общую кучу и потеряет владельца.
mats_dir, tex_dir = material_dirs(profile, asset, unique_mat)
check(os.path.dirname(mats_dir) == os.path.dirname(tex_dir),
      "materials/ и textures/ уникального материала в одной папке")

for mat in (shared_mat, unique_mat):
    bpy.data.materials.remove(mat)


# -- 8. экспорт фикстуры для Godot-половины ---------------------------------

print("\n=== 8. экспорт фикстуры ===")
for profile in prefs.profiles:
    profile.create_import_file = True
bpy.ops.godot_pipeline.install_import_script()
failed = godot_pipeline.export_all_headless()
check(failed == 0, "экспорт без ошибок (%d провал(ов))" % failed)


print("")
if failures:
    print("=== ИТОГ: ПРОВАЛОВ %d" % len(failures))
    for item in failures:
        print("  - " + item)
    sys.exit(1)
print("=== ИТОГ: ВСЁ ЗЕЛЁНОЕ")
sys.exit(0)
