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
    # Ucupaint называет запечённое по дереву слоёв, а не по материалу.
    ("Ucupaint MAT_architect_artifact Color", "T_architect_artifact_albedo"),
    ("UCU_MAT_Door Normal", "T_Door_n"),
    # Уже испорченное прежним ренеймером имя чинится повторным прогоном.
    ("T_Ucupaint_MAT_architect_artifact_albedo", "T_architect_artifact_albedo"),
    # Конвертация в Ucupaint 3.0 дописывает « 1», Blender — «.001».
    ("T_Door_albedo 1", "T_Door_albedo"),
    ("MAT_door Color.001", "T_door_albedo"),
    # Каналы 3.0: высота отдельно от нормали, векторное смещение — не высота.
    ("MAT_door Height", "T_door_height"),
    ("MAT_door Vector Displacement", "T_door_vdm"),
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

print("--- цели запечки Ucupaint 3.0 ---")
# Тест идёт с --factory-startup, без Ucupaint, поэтому дерево слоёв — заглушка
# с теми же полями, что читает ренеймер.
from types import SimpleNamespace as NS                        # noqa: E402


def fake_target(name, image_name=""):
    node = NS(image=NS(name=image_name)) if image_name else None
    return NS(name=name, data_type='IMAGE', baked_node=name if node else ""), node


targets = [
    fake_target("T_Door_albedo 1", "T_Door_albedo 1"),        # конвертированная
    fake_target("MAT_crate Roughness"),                       # канал печёт сюда
    fake_target("MAT_crate ORM"),                             # цель ORM каналов
    fake_target("MAT_crate Normal without Height"),           # запасная Ucupaint
]
nodes = {t.baked_node: n for t, n in targets if n is not None}
tree = NS(name="Ucupaint MAT_crate", nodes=NS(get=nodes.get), yp=NS(
    channels=[NS(bake_target_name=n) for n in
              ("T_Door_albedo 1", "MAT_crate Roughness", "MAT_crate ORM")],
    bake_targets=[t for t, _ in targets]))
got = {p.old_name: p.new_name for p in ucupaint.plan_target_renames([tree])}
check(got == {"T_Door_albedo 1": "T_Door_albedo",
              "MAT_crate Roughness": "T_crate_roughness",
              "MAT_crate ORM": "T_crate_orm"},
      "цели по конвенции, запасная не тронута (получено %r)" % got)


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
             "T_door_height.png", "T_door_vdm.png"):
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


# -- 9. сборщик на Geometry Nodes, имена, контракт клетки ---------------------
# После экспорта фикстуры намеренно: всё, что заводится здесь, в .glb для
# Godot-половины не попадает.

print("\n=== 9. сборщик на Geometry Nodes, имена, клетка ===")
from godot_pipeline.exporter import materials_of                 # noqa: E402
from godot_pipeline.physics import PREVIEW_MATERIAL              # noqa: E402

kit_mat = bpy.data.materials.new("MAT_kit")
piece_mesh = bpy.data.meshes.new("kit_piece")
piece_mesh.from_pydata([(-1.0, -1.0, 0.0), (1.0, -1.0, 0.0), (1.0, 1.0, 0.0), (-1.0, 1.0, 0.0)],
                       [], [(0, 1, 2, 3)])
piece_mesh.materials.append(kit_mat)
piece = bpy.data.objects.new("kit_piece", piece_mesh)
scene.collection.objects.link(piece)

# Сборщик: берёт геометрию детали через Object Info — ровно как сборщик комнат.
assembler = bpy.data.node_groups.new("GN_test_assembler", 'GeometryNodeTree')
assembler.is_modifier = True
assembler.interface.new_socket("Geometry", in_out='INPUT', socket_type='NodeSocketGeometry')
assembler.interface.new_socket("Geometry", in_out='OUTPUT', socket_type='NodeSocketGeometry')
group_out = assembler.nodes.new('NodeGroupOutput')
info = assembler.nodes.new('GeometryNodeObjectInfo')
info.inputs["Object"].default_value = piece
assembler.links.new(info.outputs["Geometry"], group_out.inputs[0])

tile_coll = bpy.data.collections.new("SM_room_T")
scene.collection.children.link(tile_coll)
tile = bpy.data.objects.new("room_T", bpy.data.meshes.new("room_T"))
tile_coll.objects.link(tile)
tile.modifiers.new("assembler", 'NODES').node_group = assembler
bpy.context.view_layer.update()

check([m.name for m in materials_of([tile])] == ["MAT_kit"],
      "материал сборщика найден в вычисленном меше (получено %s)"
      % [m.name for m in materials_of([tile])])

preview = bpy.data.materials.get(PREVIEW_MATERIAL) or bpy.data.materials.new(PREVIEW_MATERIAL)
proxy = bpy.data.objects.new("CO_room_T_Box", bpy.data.meshes.new("CO_room_T_Box"))
proxy.data.materials.append(preview)
tile_coll.objects.link(proxy)
check(PREVIEW_MATERIAL not in [m.name for m in materials_of([tile, proxy])],
      "служебный материал прокси не считается материалом ассета")

from godot_pipeline.naming import footprint_of                  # noqa: E402

for name, expected in (("SM_room_A_shell_3x2x1", (3, 2, 1)), ("SM_room_T", (1, 1, 1)),
                       ("SM_room_T_0x2x1", (1, 1, 1)), ("SM_stairs_1x2x2", (1, 2, 2))):
    check(footprint_of(name) == expected,
          "footprint из имени %s -> %s (получено %s)" % (name, expected, footprint_of(name)))

# Кит 8 м: клетка-куб, footprint по умолчанию — одна клетка.
chunk = next(p for p in prefs.profiles if p.name == "Level Chunk")
chunk.cell_size = 8.0
chunk.cell_height = 8.0
tile_coll.godot.is_asset = True
tile_coll.godot.profile = "Level Chunk"
tile_coll.godot.dest_dir = "assets"


def tile_messages():
    return [i.message for i in validate_mod.validate(bpy.context, prefs, [tile_coll])]


def move_vertex(index, axis, value):
    setattr(piece_mesh.vertices[index].co, axis, value)
    piece_mesh.update()
    bpy.context.view_layer.update()


got = tile_messages()
check(not any("past the edge" in m or "height limit" in m for m in got),
      "тайл внутри клетки претензий не вызывает")

move_vertex(1, "x", 4.5)
check(any("past the edge" in m for m in tile_messages()),
      "выступ за грань клетки ловится по вычисленному мешу")

# Коробка 2×2: те же 4.5 м законны, граница — ±8.
tile_coll.name = "SM_room_T_2x2x1"
check(not any("past the edge" in m for m in tile_messages()),
      "коробка 2x2 проходит там, где одна клетка нарушила бы контракт")
move_vertex(1, "x", 8.5)
check(any("past the edge" in m and "2x2x1" in m for m in tile_messages()),
      "выступ за footprint 2x2 ловится")
move_vertex(1, "x", 1.0)

move_vertex(2, "z", 9.0)
check(any("height limit" in m for m in tile_messages()), "превышение высоты ловится")
tile_coll.name = "SM_room_T_1x1x2"
check(not any("height limit" in m for m in tile_messages()),
      "в два уровня высотой те же 9 м законны")
tile_coll.name = "SM_room_T"
move_vertex(2, "z", 0.0)

chunk.cell_size = 0.0
chunk.cell_height = 0.0
move_vertex(1, "x", 9.5)
check(not any("past the edge" in m for m in tile_messages()), "с нулевой клеткой проверка молчит")

check(not any("same name as its file" in m for m in tile_messages()),
      "объект без префикса ассета не путается с файлом")
tile.name = "SM_room_T"
got = tile_messages()
check(any("same name as its file" in m for m in got), "объект с именем файла ловится")
check(any("mesh data named" in m for m in got), "данные меша с чужим именем отмечены")
tile.name = "room_T"

print("--- служебный материал прокси не уезжает в .glb ---")
import json                                                      # noqa: E402
import struct                                                    # noqa: E402
from godot_pipeline.exporter import asset_paths, export_asset    # noqa: E402

piece_mesh.vertices[1].co.x = 1.0
piece_mesh.update()
result = export_asset(bpy.context, prefs, tile_coll, OUT, chunk)
glb_path = asset_paths(OUT, chunk, tile_coll)[0]
check(result.status != "failed" and os.path.isfile(glb_path),
      "тайл экспортирован (%s)" % result.status)
with open(glb_path, "rb") as handle:
    handle.read(12)
    length, _ = struct.unpack("<II", handle.read(8))
    gltf = json.loads(handle.read(length))
names = [m.get("name") for m in gltf.get("materials", [])]
check(PREVIEW_MATERIAL not in names, "в .glb нет %s (материалы: %s)" % (PREVIEW_MATERIAL, names))
check("MAT_kit" in names, "настоящий материал сборщика в .glb на месте")
check(proxy.data.materials[0] == preview, "после экспорта подсветка прокси вернулась в слот")


# -- 10. контракт рига персонажа --------------------------------------------
# Тоже после экспорта фикстуры: персонаж здесь только валидируется.

print("\n=== 10. контракт рига ===")
from godot_pipeline import rigs                                  # noqa: E402

for rig_type in ('HUMANOID', 'CRAWLER', 'QUADRUPED'):
    schema = rigs.schema(rig_type)
    check(schema is not None and {"Root", "Head"} <= set(schema.required)
          and set(schema.required) <= schema.allowed,
          "эталон %s читается, Root и Head обязательны" % rig_type.lower())
check(len(rigs.schema('HUMANOID').allowed) == 56,
      "гуманоид — все 56 костей SkeletonProfileHumanoid")
check(rigs.schema('NONE') is None, "«не персонаж» эталона не имеет")

humanoid = rigs.schema('HUMANOID')
rig_coll = bpy.data.collections.new("SK_testrig")
scene.collection.children.link(rig_coll)
rig_coll.godot.is_asset = True
rig_coll.godot.profile = "Character"
rig_coll.godot.dest_dir = "assets"
rig_coll.godot.rig_type = 'HUMANOID'

bpy.ops.object.armature_add(enter_editmode=True)
rig = bpy.context.active_object
rig.name = "testrig"
edit = rig.data.edit_bones
edit[0].name = "Root"
for index, bone_name in enumerate(humanoid.required[1:] + ("Neck",)):
    bone = edit.new(bone_name)
    bone.head = (0.1 * index, 0.0, 0.0)
    bone.tail = (0.1 * index, 0.0, 0.1)
    bone.parent = edit[0]
bpy.ops.object.mode_set(mode='OBJECT')
for coll in list(rig.users_collection):
    coll.objects.unlink(rig)
rig_coll.objects.link(rig)

rig_mat = bpy.data.materials.new("MAT_testrig")
rig_parts = {}
for part in ("testrig_body", "testrig_head", "testrig_arms"):
    mesh = bpy.data.meshes.new(part)
    mesh.from_pydata([(0.0, 0.0, 0.0), (0.1, 0.0, 0.0), (0.0, 0.1, 0.0)], [], [(0, 1, 2)])
    mesh.uv_layers.new()
    mesh.materials.append(rig_mat)
    obj = bpy.data.objects.new(part, mesh)
    obj.parent = rig
    rig_coll.objects.link(obj)
    rig_parts[part] = obj
bpy.context.view_layer.update()

RIG_MARKERS = ("needs an armature", "not a deform bone", "duplicate suffix", "reference list",
               "lacks required", "unapplied", "no separate", "not named MAT_")


def rig_issues():
    return [i for i in validate_mod.validate(bpy.context, prefs, [rig_coll])
            if any(marker in i.message for marker in RIG_MARKERS)]


got = rig_issues()
check(not got, "риг по контракту претензий не вызывает (получено %s)" % [i.message for i in got])

bones = rig.data.bones
bones["LeftLowerArm"].name = "LeftLowerArm.001"
got = rig_issues()
check(any(i.level == 'ERROR' and "duplicate suffix" in i.message for i in got),
      "автосуффикс .001 у кости — ошибка")
check(any("lacks required" in i.message and "LeftLowerArm" in i.message for i in got),
      "переименованная обязательная кость числится недостающей")
bones["LeftLowerArm.001"].name = "forearm.l"
check(any(i.level == 'ERROR' and "reference list" in i.message for i in rig_issues()),
      "кость мимо эталона — ошибка")
bones["forearm.l"].name = "LeftLowerArm"

bones["Root"].use_deform = False
check(any("Root" in i.message and "not a deform bone" in i.message for i in rig_issues()),
      "недеформирующий Root при deform-only ловится")
bones["Root"].use_deform = True

rig_parts["testrig_head"].name = "testrig_skull"
check(any("no separate head" in i.message for i in rig_issues()), "голова без суффикса _head ловится")
rig_parts["testrig_head"].name = "testrig_head"

rig_mat.name = "palette"
check(any("not named MAT_" in i.message for i in rig_issues()), "материал без MAT_ ловится")
rig_mat.name = "MAT_testrig"

rig_parts["testrig_body"].rotation_euler.x = 1.5708
bpy.context.view_layer.update()
check(any("unapplied rotation" in i.message for i in rig_issues()), "неприменённый поворот ловится")

bones["Root"].name = "root.001"
rig_coll.godot.rig_type = 'NONE'
check(not rig_issues(), "у «не персонажа» контракт рига молчит")
rig_coll.godot.rig_type = 'CRAWLER'
check(any("reference list" in i.message and "LeftUpperLeg" in i.message for i in rig_issues()),
      "ноги гуманоида мимо эталона ползуна")

print("--- тип корня поверх тела ---")
rig_coll.godot.rig_type = 'HUMANOID'
bones["root.001"].name = "Root"
character = next(p for p in prefs.profiles if p.name == "Character")
check(character.root_type == 'NONE', "у Character по умолчанию корень Node3D")


def root_warnings():
    return [i.message for i in validate_mod.validate(bpy.context, prefs, [rig_coll])
            if "shapeless body" in i.message]


check(not root_warnings(), "корень Node3D претензий не вызывает")
character.root_type = 'CHAR'
check(any("CharacterBody3D" in m for m in root_warnings()),
      "корень-тело у персонажа ловится")
character.root_type = 'NONE'
interactive = next(p for p in prefs.profiles if p.name == "Interactive")
check(interactive.root_type == 'NONE',
      "у Interactive по умолчанию корень Node3D, Reset Profile ловушку не вернёт")


# -- 11. Collection per Object: префикс ассета ------------------------------

print("\n=== 11. Collection per Object: префикс ===")
check([p.collection_prefix for p in prefs.profiles] == ["SK_", "SM_", "SM_", "SM_"],
      "префиксы профилей по умолчанию: Character SK_, остальные SM_ (получено %s)"
      % [p.collection_prefix for p in prefs.profiles])

split_home = bpy.data.collections.new("_split")
scene.collection.children.link(split_home)


def split(names, **options):
    """Объекты с этими именами в _split, выделены, — и оператор над ними."""
    bpy.ops.object.select_all(action='DESELECT')
    objects = []
    for name in names:
        obj = bpy.data.objects.new(name, None)
        split_home.objects.link(obj)
        obj.select_set(True)
        objects.append(obj)
    bpy.context.view_layer.active_layer_collection = \
        bpy.context.view_layer.layer_collection.children["_split"]
    bpy.ops.godot_pipeline.split_to_collections('EXEC_DEFAULT', **options)
    return [[c.name for c in obj.users_collection] for obj in objects]


check(split(["chair_A"], profile="Prop") == [["SM_chair_A"]],
      "статика получает префикс своего профиля")
check(split(["walker"], profile="Character") == [["SK_walker"]],
      "персонаж получает SK_")
check(bpy.data.objects["walker"].name == "walker", "имя объекта остаётся без префикса")
check(split(["SM_shelf_A"], profile="Prop") == [["SM_shelf_A"]], "SM_SM_ не получается")
check(split(["desk_A-col"], profile="Prop") == [["SM_desk_A"]],
      "суффикс Godot срезан, префикс добавлен")
check(split(["lamp_A"], profile="Prop", prefix_mode='NONE') == [["lamp_A"]],
      "без префикса — имя объекта как было")
check(split(["vent_A"], profile="Prop", prefix_mode='CUSTOM', custom_prefix="PR_")
      == [["PR_vent_A"]], "свой префикс")


print("")
if failures:
    print("=== ИТОГ: ПРОВАЛОВ %d" % len(failures))
    for item in failures:
        print("  - " + item)
    sys.exit(1)
print("=== ИТОГ: ВСЁ ЗЕЛЁНОЕ")
sys.exit(0)
