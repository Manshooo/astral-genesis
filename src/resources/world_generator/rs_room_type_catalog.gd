## res://src/resources/world_generator/rs_room_type_catalog.gd
## Каталог типов помещений: что вообще встречается в комплексе и на какой
## глубине. Данные — `data/room_type_catalog.tres`, правятся в редакторе.
##
## Каталог живёт В БИБЛИОТЕКЕ пресетов (RS_RoomPresetLibrary.type_catalog), а не
## отдельным аргументом генератора: у `generate_run(seed, library)` пять
## вызывающих — игра, оба редакторских тула и два прогона в `dev/`, — и лишний
## параметр они бы разъехались передавать. Библиотека же и так «каталог того, из
## чего складывается комплекс», типы — её вторая ось.
@tool
class_name RS_RoomTypeCatalog
extends Resource

## Порядок важен для ДЕТЕРМИНИЗМА: розыгрыш идёт по массиву, и перестановка
## строк меняет то, что выпадет на том же сиде. Это не повод бояться правок —
## забег хранит сид и прогресс, а не комнаты, — но объясняет, почему граф
## «поехал» после безобидной на вид сортировки каталога.
@export var types: Array[RS_RoomType] = []

## Вес исхода «у комнаты нет типа» — безликое помещение, каких в комплексе
## большинство. Наравне с весами типов участвует в том же броске: без него
## каждая комната обязана была бы чем-то быть, и тематические помещения
## перестали бы читаться как особенные.
@export var untyped_weight: float = 4.0


## Разыгрывает тип для узла глубины [param depth]. Возвращает `&""`, если выпало
## «без типа» или ни один тип эту глубину не покрывает.
##
## Бросок делается ВСЕГДА, даже когда подходящих типов нет: rng — общий на всю
## генерацию, и пропуск броска на одном узле сдвинул бы всё, что разыгрывается
## после него. Детерминированность по сиду тут дороже сэкономленного вызова.
func pick_for_depth(depth: int, rng: RandomNumberGenerator) -> StringName:
	var eligible: Array[RS_RoomType] = []
	var total := maxf(untyped_weight, 0.0)
	for type: RS_RoomType in types:
		if type == null or type.weight <= 0.0 or not type.covers_depth(depth):
			continue
		eligible.append(type)
		total += type.weight

	var roll := rng.randf()
	if total <= 0.0:
		return &""

	var acc := maxf(untyped_weight, 0.0)
	roll *= total
	if roll <= acc:
		return &""
	for type: RS_RoomType in eligible:
		acc += type.weight
		if roll <= acc:
			return type.id
	return &""


func by_id(id: StringName) -> RS_RoomType:
	for type: RS_RoomType in types:
		if type != null and type.id == id:
			return type
	return null


## Ключи всех типов каталога в порядке объявления — для выпадающих списков
## инструментов и для проверок.
func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for type: RS_RoomType in types:
		if type != null and type.id != &"":
			out.append(type.id)
	return out


## Имя типа для инструментов и логов. Неизвестный ключ возвращается как есть —
## это не ошибка каталога, а пресет, чей тип из каталога убрали.
func label_of(id: StringName) -> String:
	if id == &"":
		return "—"
	var type := by_id(id)
	return type.label() if type else String(id)


## Расхождения каталога — зовётся из проверок и инструментов, не в генерации.
func validate() -> Array[String]:
	var problems: Array[String] = []
	var seen := {}
	for i in types.size():
		var type := types[i]
		if type == null:
			problems.append("null-тип в позиции %d" % i)
			continue
		if type.id == &"":
			problems.append("тип в позиции %d без id" % i)
			continue
		if seen.has(type.id):
			problems.append("id «%s» повторяется" % type.id)
		seen[type.id] = true
		if type.depth_min > type.depth_max:
			problems.append(
				"«%s»: depth_min=%d больше depth_max=%d — тип не выпадет никогда"
				% [type.id, type.depth_min, type.depth_max]
			)
	return problems
