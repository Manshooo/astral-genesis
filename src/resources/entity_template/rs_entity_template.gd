## res://src/resources/entity_template/rs_entity_template.gd
## Шаблон GECS-сущности: из него тул («Шаблоны», addons/game_design_tool) генерирует .tscn с корнем [Entity]. Чистые данные.
## Русские подписи — отдельным списком (_get_property_list), настоящие @export прячутся (_validate_property) и остаются
## местом хранения. Вики: [[Редакторские инструменты]].
@tool
class_name RS_EntityTemplate
extends Resource

## Скрипт [Entity]: энтити в проекте — узел (в т.ч. Node3D) со скриптом `extends Entity`.
const ENTITY_SCRIPT := preload("res://addons/gecs/ecs/entity.gd")

## Корни-контейнеры, которым тул сам навешивает скрипт Entity, сохраняя нативный тип.
const PLAIN_ROOT_CLASSES := ["Node", "Node2D", "Node3D"]

## Подпись в инспекторе → имя свойства; порядок словаря = порядок полей.
const LABELS := {
	"Имя": &"display_name",
	"Базовая сцена": &"base_scene",
	"Скрипт сущности": &"entity_script",
	"Компоненты": &"components",
	"Метки": &"tags",
}

## Имя в списке шаблонов и по умолчанию для новой сцены.
@export var display_name: String = ""

## Базовая сцена (необязательная): инстанцируется корнем со всей структурой и компонентами; корень-контейнер получит скрипт Entity.
@export var base_scene: PackedScene

## Скрипт-[Entity] для корня при создании; пусто = базовый. Не применяется, если корень base_scene уже Entity со своим скриптом.
@export var entity_script: Script

## Компоненты, ДОБАВЛЯЕМЫЕ к лежащим в базовой сцене. Если база — уже Entity, компоненты место в ней, а список пуст
## (один источник правды; дубль лёг бы вторым экземпляром). Нужен, когда базы нет, корень — контейнер без скрипта
## (component_resources ещё нет) или несколько шаблонов делят одну сцену.
@export var components: Array[Component] = []

## Метки для группировки и поиска; на генерацию не влияют.
@export var tags: Array[StringName] = []


## Сколько компонентов получит сущность: свои плюс лежащие в корне базовой сцены. Сцену не инстанцируем — читаем состояние упаковки (как RS_RoomLayout.door_sides_of_scene).
func component_count() -> int:
	return components.size() + _base_scene_component_count()


func _base_scene_component_count() -> int:
	if base_scene == null:
		return 0
	var state := base_scene.get_state()
	if state.get_node_count() == 0:
		return 0
	for i in state.get_node_property_count(0):  # 0 — корень сцены
		if state.get_node_property_name(0, i) == &"component_resources":
			var value = state.get_node_property_value(0, i)
			return (value as Array).size() if value is Array else 0
	return 0


## Собирает корневой узел для упаковки в PackedScene (узел не в дереве). Пустая база → скрипт Entity; корень Entity — как есть;
## контейнер без скрипта — получает скрипт Entity; чужой тип/скрипт — как есть, компоненты пропускаем. Компоненты копируются глубоко.
## [param root_name] пусто = display_name.
func build_entity(root_name := "") -> Node:
	var root: Node = null

	if base_scene != null:
		# GEN_EDIT_STATE_INSTANCE: pack() аккуратно сохранит инстансы под-сцен.
		root = base_scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		if not (root is Entity):
			if root.get_script() == null and root.get_class() in PLAIN_ROOT_CLASSES:
				root.set_script(_root_script())  # контейнер → Entity на месте
			else:
				push_warning(
					"RS_EntityTemplate '%s': корень base_scene (%s%s) не Entity и не пустой контейнер — оставлен как есть, компоненты пропущены."
					% [display_name, root.get_class(), ", со скриптом" if root.get_script() else ""]
				)

	if root == null:
		root = Node.new()
		root.set_script(_root_script())

	var final_name := root_name if root_name != "" else display_name
	if final_name != "":
		root.name = final_name

	if root is Entity:
		var entity := root as Entity
		for c in components:
			if c != null:
				entity.component_resources.append(c.duplicate(true))

	return root


## Скрипт для корня: entity_script, иначе базовый.
func _root_script() -> Script:
	return entity_script if entity_script != null else ENTITY_SCRIPT


#region Русские подписи в инспекторе
## Настоящие свойства прячем из инспектора, оставляя хранение: иначе два поля на одно значение.
func _validate_property(property: Dictionary) -> void:
	if property.name in LABELS.values():
		property.usage = PROPERTY_USAGE_STORAGE


## Русские двойники — только для редактора (без STORAGE).
func _get_property_list() -> Array[Dictionary]:
	return [
		_editor_property("Имя", TYPE_STRING),
		_editor_property("Базовая сцена", TYPE_OBJECT, PROPERTY_HINT_RESOURCE_TYPE, "PackedScene"),
		_editor_property("Скрипт сущности", TYPE_OBJECT, PROPERTY_HINT_RESOURCE_TYPE, "Script"),
		_editor_property(
			"Компоненты",
			TYPE_ARRAY,
			PROPERTY_HINT_TYPE_STRING,
			"%d/%d:%s" % [TYPE_OBJECT, PROPERTY_HINT_RESOURCE_TYPE, "Component"]
		),
		_editor_property("Метки", TYPE_ARRAY, PROPERTY_HINT_TYPE_STRING, "%d:" % TYPE_STRING_NAME),
	]


func _editor_property(
	label: String, type: int, hint: int = PROPERTY_HINT_NONE, hint_string: String = ""
) -> Dictionary:
	return {
		"name": label,
		"type": type,
		"hint": hint,
		"hint_string": hint_string,
		"usage": PROPERTY_USAGE_EDITOR,
	}


func _get(property: StringName) -> Variant:
	var backing = LABELS.get(property)
	return get(backing) if backing != null else null


func _set(property: StringName, value: Variant) -> bool:
	var backing = LABELS.get(property)
	if backing == null:
		return false
	set(backing, value)
	return true
#endregion
