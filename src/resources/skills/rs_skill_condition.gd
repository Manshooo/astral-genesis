## res://src/resources/skills/rs_skill_condition.gd
## Условие ранга навыка: действие, которое усиливает значение ЭТОГО ранга на condition_bonus. Данные (data/skill_tree.tres), но тип
## фиксирован enum'ом — за каждым свой источник событий (S_SkillConditions, RunStats). Прогресс — в PlayerSkillSave, переживает забеги.
class_name RS_SkillCondition
extends Resource

enum Type {
	## Метры пешком по клеткам, НОВЫМ в этом забеге (кругами в колбе не набрать — RS_RunStats.credit_cell_distance).
	DISTANCE_NEW_CELLS,
	## Разные виды тел за всю игру, не слабее min_body_class.
	CAPTURE_KINDS,
}

@export var type: Type = Type.DISTANCE_NEW_CELLS
## Сколько нужно: метры или штуки.
@export var target: float = 1.0
## Для CAPTURE_KINDS: класс тела, с которого захват идёт в зачёт.
@export_range(0, 5) var min_body_class: int = 0
## Ключ перевода описания; пусто — по умолчанию для типа (describe).
@export var description_key: StringName = &""


## Описание для карточки: «Пройти 1 км по новым клеткам».
func describe() -> String:
	var key := description_key
	if key == &"":
		key = _default_key()
	var text := TranslationServer.translate(key)
	if type == Type.CAPTURE_KINDS:
		return text % [int(target), min_body_class]
	return text % target_text(target)


## Прогресс или цель словами с единицей: «0,4 км» / «2 вида».
func target_text(amount: float) -> String:
	match type:
		Type.DISTANCE_NEW_CELLS:
			var km := amount / 1000.0
			var text := String.num(km, 2).rstrip("0").rstrip(".") if km < 10.0 else str(int(km))
			if TranslationServer.get_locale().begins_with("ru"):
				text = text.replace(".", ",")
			return TranslationServer.translate(&"SKILL_COND_KM") % text
		_:
			return str(int(amount))


## «0,4 км из 1 км» — для строки условия.
func progress_text(progress: float) -> String:
	var shown := minf(progress, target)
	if type == Type.CAPTURE_KINDS:
		return "%d / %d" % [int(shown), int(target)]
	return TranslationServer.translate(&"SKILL_COND_PROGRESS") % [target_text(shown), target_text(target)]


func is_met(progress: float) -> bool:
	return progress >= target


## Зачитывает ли условие тело такого класса (различает только захват).
func accepts_body_class(body_class: int) -> bool:
	return type != Type.CAPTURE_KINDS or body_class >= min_body_class


func _default_key() -> StringName:
	match type:
		Type.CAPTURE_KINDS:
			return &"SKILL_COND_CAPTURE_KINDS"
		_:
			return &"SKILL_COND_DISTANCE"
