## res://src/resources/skills/rs_skill_condition.gd
## Условие ранга навыка: действие, выполнив которое душа усиливает значение
## ЭТОГО ранга на бонус навыка (RS_SkillDefinition.condition_bonus). «Делаешь
## действия — за это прокачиваешься» (карточка «Игровой цикл — от и до» §4.1).
##
## Условие — данные, а не код в системе: что считать и сколько нужно, правится в
## data/skill_tree.tres. Но ТИП фиксирован перечислением, потому что за каждым
## типом стоит свой источник событий (S_SkillConditions считает дистанцию,
## RunStats передаёт захваты) — новый тип стоит и строки здесь, и того, кто о нём
## сообщит SkillProgression.
##
## Прогресс условия здесь не живёт: ресурс — описание, общее для всех сейвов.
## Прогресс копится в PlayerSkillSave и переживает забеги — учится душа, не тело.
class_name RS_SkillCondition
extends Resource

enum Type {
	## Метры, пройденные пешком по клеткам, НОВЫМ в этом забеге. Урок Elder
	## Scrolls: «пробеги километр» без контекста выполняют, бегая кругами в
	## колбе. Контекст — в RS_RunStats.credit_cell_distance.
	DISTANCE_NEW_CELLS,
	## Разные виды тел (сцены), захваченные за всю игру. Считаются только тела
	## не слабее [member min_body_class]: «захвати три вида» иначе закрывалось бы
	## тремя трупами.
	CAPTURE_KINDS,
}

@export var type: Type = Type.DISTANCE_NEW_CELLS
## Сколько нужно: метры для DISTANCE_NEW_CELLS, штуки для CAPTURE_KINDS.
@export var target: float = 1.0
## Для CAPTURE_KINDS: класс тела (E_Body.body_class), с которого захват идёт в
## зачёт. Для остальных типов не читается.
@export_range(0, 5) var min_body_class: int = 0
## Ключ перевода описания. Пусто — по умолчанию для типа (см. [method describe]).
## Строка получает цель в читаемом виде (см. [method target_text]) и, у захвата,
## ещё и класс.
@export var description_key: StringName = &""


## Описание условия для карточки: «Пройти 1 км по новым клеткам».
func describe() -> String:
	var key := description_key
	if key == &"":
		key = _default_key()
	var text := TranslationServer.translate(key)
	if type == Type.CAPTURE_KINDS:
		return text % [int(target), min_body_class]
	return text % target_text(target)


## Значение прогресса или цели словами с единицей: «0,4 км» / «2 вида».
## Дробная запятая — по языку, как у эссенции в экране навыков.
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


## «0,4 км из 1 км» — прогресс для строки условия.
func progress_text(progress: float) -> String:
	var shown := minf(progress, target)
	if type == Type.CAPTURE_KINDS:
		return "%d / %d" % [int(shown), int(target)]
	return TranslationServer.translate(&"SKILL_COND_PROGRESS") % [target_text(shown), target_text(target)]


func is_met(progress: float) -> bool:
	return progress >= target


## Зачитывает ли условие тело такого класса. Только захват различает классы;
## остальные типы классом не интересуются.
func accepts_body_class(body_class: int) -> bool:
	return type != Type.CAPTURE_KINDS or body_class >= min_body_class


func _default_key() -> StringName:
	match type:
		Type.CAPTURE_KINDS:
			return &"SKILL_COND_CAPTURE_KINDS"
		_:
			return &"SKILL_COND_DISTANCE"
