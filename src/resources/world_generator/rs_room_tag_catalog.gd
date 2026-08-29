## res://src/resources/world_generator/rs_room_tag_catalog.gd
## Словарь структурных тегов комнат: какие теги вообще есть в проекте и что
## каждый из них значит. Данные — `data/room_tag_catalog.tres`.
##
## До него список тегов НИГДЕ не был записан: вкладка пресетов, «Генератор
## мира» и Room Wizard собирали его обходом `preset.tags`. Работало, но у тега
## не было ни описания, ни способа отличить настоящий тег от опечатки —
## `verticalhub` выглядел в облаке ровно так же полноценно, как `vertical_hub`.
##
## Лежит В БИБЛИОТЕКЕ пресетов (RS_RoomPresetLibrary.tag_catalog) рядом с
## каталогом типов и по той же причине: у `generate_run(seed, library)` пять
## вызывающих, и лишний параметр они бы разъехались передавать.
##
## В ОТЛИЧИЕ от RS_RoomTypeCatalog порядок записей здесь ни на что не влияет:
## теги не разыгрываются, по ним фильтруют. Сортировать словарь можно свободно —
## граф на том же сиде не поедет.
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


## Ключи всех тегов словаря — для облаков тегов в инструментах.
func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for tag: RS_RoomTag in tags:
		if tag != null and tag.id != &"":
			out.append(tag.id)
	return out


## Имя тега для инструментов. Неизвестный ключ возвращается как есть — это не
## ошибка словаря, а тег, описание которому ещё не написали.
func label_of(id: StringName) -> String:
	var tag := by_id(id)
	return tag.label() if tag else String(id)


## Описание тега или "" — вызывающий сам решает, что показать вместо него
## (инструменты пишут «нет описания», а не молчат: пустая строка под чипом
## читалась бы как «тег ничего не значит»).
func description_of(id: StringName) -> String:
	var tag := by_id(id)
	return tag.description if tag else ""


## Заводит запись под новый ключ и возвращает её; существующую не трогает.
## Нужна инструментам: тег появляется в момент, когда его вешают на пресет, а не
## когда для него написали описание.
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


## Расхождения словаря — зовётся из проверок и инструментов, не в генерации.
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
