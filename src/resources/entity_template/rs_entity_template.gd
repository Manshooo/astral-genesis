## res://src/resources/entity_template/rs_entity_template.gd
## Шаблон GECS-сущности для быстрого создания энтити (см. tool «Шаблоны сущностей»,
## addons/entity_template_tool). Чистые данные: имя, необязательная базовая сцена
## и набор компонентов. Из шаблона тул генерирует .tscn с корневым [Entity].
##
## Подписи полей в инспекторе — русские, а имена свойств, ключи в .tres и вызовы
## в коде остаются английскими: Godot берёт подпись прямо из имени свойства, так
## что русские названия отдаются отдельным списком (_get_property_list), а
## настоящие @export-поля прячутся из инспектора (_validate_property), оставаясь
## местом ХРАНЕНИЯ. Переименовать сами свойства в кириллицу было бы проще, но это
## утащило бы кириллицу в ключи .tres и в код тула.
@tool
class_name RS_EntityTemplate
extends Resource

## Скрипт [Entity]. В проекте энтити — это узел (в т.ч. Node3D) с
## навешенным скриптом `extends Entity` (см. vertical_hub_1.gd), а не отдельный
## тип узла: Node3D — это Node, поэтому скрипт Entity к нему цепляется.
const ENTITY_SCRIPT := preload("res://addons/gecs/ecs/entity.gd")

## Обычные типы-контейнеры, чей корень тул сам превращает в Entity, навесив
## скрипт и сохранив нативный тип (Node3D остаётся пространственным).
const PLAIN_ROOT_CLASSES := ["Node", "Node2D", "Node3D"]

## Подпись в инспекторе → имя настоящего свойства. Порядок словаря задаёт порядок
## полей в инспекторе (словари в GDScript хранят порядок вставки).
const LABELS := {
	"Имя": &"display_name",
	"Базовая сцена": &"base_scene",
	"Скрипт сущности": &"entity_script",
	"Компоненты": &"components",
	"Метки": &"tags",
}

## Для читаемости в списке шаблонов и как имя по умолчанию для новой сцены.
@export var display_name: String = ""

## Необязательная базовая сцена. Если задана — новая сцена инстанцирует её как
## корень со ВСЕЙ структурой (включая вложенные инстансы) и со всеми её
## компонентами. Если корень базовой сцены — обычный контейнер (Node/Node2D/Node3D)
## без своего скрипта, тул сам навесит на него скрипт Entity (см. entity_script),
## сохранив тип. Если пусто — корнем станет узел со скриптом Entity.
@export var base_scene: PackedScene

## Какой скрипт-[Entity] вешать на корень при авто-конвертации/создании с нуля.
## Должен наследовать [Entity] (напр. скрипт комнаты `extends Entity`). Пусто =
## базовый [Entity]. НЕ применяется, если корень base_scene уже [Entity] со своим
## скриптом — тогда его скрипт сохраняется.
@export var entity_script: Script

## Компоненты, которые ДОБАВЯТСЯ к тем, что уже лежат в базовой сцене.
##
## ПРАВИЛО: если базовая сцена — уже [Entity], компоненты место в НЕЙ, а этот
## список остаётся пустым (так устроен шаблон «Тело»). Один источник правды:
## сцена, открытая напрямую, должна быть полноценной сущностью, а не половиной,
## которую дособирает тул. Дублировать сюда компоненты сцены нельзя — при сборке
## они легли бы в component_resources вторым экземпляром того же типа.
##
## Список нужен в трёх случаях, где положить компоненты в сцену НЕЛЬЗЯ или НЕ
## НУЖНО:
##   - базовой сцены нет вовсе (шаблон с нуля) — тогда это единственное
##     содержимое будущей сущности;
##   - корень базовой сцены — обычный контейнер без скрипта (чужая сцена
##     геометрии, которую не хотим править): свойства component_resources у него
##     ещё не существует, оно появится только вместе со скриптом [Entity],
##     который навесит тул;
##   - несколько шаблонов делят ОДНУ базовую сцену и различаются данными —
##     варианты поверх общей заготовки (так шаблон «Комната» добирает
##     C_LevelNode к room_template.tscn).
@export var components: Array[Component] = []

## Произвольные метки для группировки/поиска. На генерацию не влияют.
@export var tags: Array[StringName] = []


## Сколько компонентов получит сущность из этого шаблона: свои плюс те, что уже
## лежат в корне базовой сцены. Для строки списка в доке — «(0 комп.)» у шаблона
## с полностью укомплектованной базовой сценой врало бы.
##
## Сцену НЕ инстанцируем: читаем состояние упаковки (тот же приём, что в
## RS_RoomLayout.door_directions_of_scene). Док зовёт это на каждый шаблон при
## обновлении списка, а список обновляется при открытии редактора.
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


## Собирает корневой узел из шаблона для упаковки в PackedScene. Узел не в
## дереве: вызывающий пакует/освобождает.
##   - base_scene пуста → узел со скриптом Entity (см. _root_script);
##   - корень base_scene уже Entity → сохраняется как есть;
##   - корень — обычный контейнер (Node/Node2D/Node3D) без скрипта → скрипт
##     Entity навешивается на месте, тип и структура сохраняются;
##   - иначе (чужой тип/скрипт) → оставляем как есть, компоненты пропускаем.
## Компоненты глубоко копируются и дописываются в component_resources корня-Entity.
## [param root_name] — имя корневого узла; пусто = display_name шаблона.
func build_entity(root_name := "") -> Node:
	var root: Node = null

	if base_scene != null:
		# GEN_EDIT_STATE_INSTANCE — узлы получают правки-метаданные, чтобы pack()
		# аккуратно сохранил инстансы под-сцен. Структура цела при любом edit state.
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


## Скрипт для корня: пользовательский entity_script (если задан) иначе базовый.
func _root_script() -> Script:
	return entity_script if entity_script != null else ENTITY_SCRIPT


#region Русские подписи в инспекторе
## Настоящие свойства прячем из инспектора, оставляя им хранение: показывать их
## рядом с русскими двойниками значило бы два поля на одно значение.
func _validate_property(property: Dictionary) -> void:
	if property.name in LABELS.values():
		property.usage = PROPERTY_USAGE_STORAGE


## Русские двойники: только для редактора (без STORAGE — хранит оригинал).
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
