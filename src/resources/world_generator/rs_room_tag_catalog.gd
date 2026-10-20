## res://src/resources/world_generator/rs_room_tag_catalog.gd
## Словарь структурных тегов: какие теги есть и что значат (data/room_tag_catalog.tres) — чтобы отличать тег от опечатки. Лежит в
## библиотеке пресетов (tag_catalog), как каталог типов. Порядок записей ни на что не влияет: теги не разыгрываются, по ним фильтруют.
@tool
class_name RS_RoomTagCatalog
extends Resource

@export var tags: Array[RS_RoomTag] = []


func by_id(id: StringName) -> RS_RoomTag:
	for tag: RS_RoomTag in tags:
		if tag != null and tag.id == id:
			return tag
	return null


func has_id(id: StringName) -> bool:
	return by_id(id) != null


## Ключи всех тегов — для облаков тегов в инструментах.
func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for tag: RS_RoomTag in tags:
		if tag != null and tag.id != &"":
			out.append(tag.id)
	return out


## Имя тега для инструментов; неизвестный ключ — как есть (описание ещё не написано).
func label_of(id: StringName) -> String:
	var tag := by_id(id)
	return tag.label() if tag else String(id)


## Описание тега или "": инструменты пишут «нет описания», а не молчат.
func description_of(id: StringName) -> String:
	var tag := by_id(id)
	return tag.description if tag else ""


## Заводит запись под новый ключ и возвращает её; существующую не трогает (тег появляется, когда его вешают на пресет).
func add_id(id: StringName) -> RS_RoomTag:
	var existing := by_id(id)
	if existing:
		return existing
	var tag := RS_RoomTag.new()
	tag.id = id
	tags.append(tag)
	return tag


func remove_id(id: StringName) -> void:
	var tag := by_id(id)
	if tag:
		tags.erase(tag)


## Расхождения словаря — для проверок и инструментов, не для генерации.
func validate() -> Array[String]:
	var problems: Array[String] = []
	var seen := {}
	for i in tags.size():
		var tag := tags[i]
		if tag == null:
			problems.append("null-тег в позиции %d" % i)
			continue
		if tag.id == &"":
			problems.append("тег в позиции %d без id" % i)
			continue
		if seen.has(tag.id):
			problems.append("id «%s» повторяется" % tag.id)
		seen[tag.id] = true
	return problems
