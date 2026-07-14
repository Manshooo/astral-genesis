## res://src/resources/entity_template/rs_entity_template.gd
## Шаблон GECS-сущности для быстрого создания энтити (см. tool «Шаблоны сущностей»,
## addons/entity_template_tool). Чистые данные: имя, необязательная базовая сцена
## и набор компонентов. Из шаблона тул генерирует .tscn с корневым [Entity].
@tool
class_name RS_EntityTemplate
extends Resource

## Базовый скрипт [Entity]. В проекте энтити — это узел (в т.ч. Node3D) с
## навешенным скриптом `extends Entity` (см. vertical_hub_1.gd), а не отдельный
## тип узла: Node3D — это Node, поэтому скрипт Entity к нему цепляется.
const ENTITY_SCRIPT := preload("res://addons/gecs/ecs/entity.gd")

## Обычные типы-контейнеры, чей корень тул сам превращает в Entity, навесив
## скрипт и сохранив нативный тип (Node3D остаётся пространственным).
const PLAIN_ROOT_CLASSES := ["Node", "Node2D", "Node3D"]

## Для читаемости в списке шаблонов и как имя по умолчанию для новой сцены.
@export var display_name: String = ""

## Необязательная базовая сцена. Если задана — новая сцена инстанцирует её как
## корень со ВСЕЙ структурой (включая вложенные инстансы). Если корень базовой
## сцены — обычный контейнер (Node/Node2D/Node3D) без своего скрипта, тул сам
## навесит на него скрипт Entity (см. entity_script), сохранив тип. Если пусто —
## корнем станет узел со скриптом Entity.
@export var base_scene: PackedScene

## Какой скрипт-[Entity] вешать на корень при авто-конвертации/создании с нуля.
## Должен наследовать [Entity] (напр. скрипт комнаты `extends Entity`). Пусто =
## базовый [Entity]. НЕ применяется, если корень base_scene уже [Entity] со своим
## скриптом — тогда его скрипт сохраняется.
@export var entity_script: Script

## Компоненты, которые получит созданная сущность. В инспекторе жми «+», чтобы
## добавить любой подкласс [Component] (C_Health, C_Interactable, ...).
@export var components: Array[Component] = []

## Произвольные метки для группировки/поиска. На генерацию не влияют.
@export var tags: Array[StringName] = []


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
