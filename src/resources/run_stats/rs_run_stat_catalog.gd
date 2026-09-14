## res://src/resources/run_stats/rs_run_stat_catalog.gd
## Из чего складывается сводка забега: какие показатели показывать и в каком
## порядке. Данные — `data/run_stat_catalog.tres`, правятся в редакторе.
##
## Экран итогов не знает ни одного показателя по имени: он идёт по этому
## каталогу и просит отформатировать значение. Поэтому «добавить в сводку
## артефакты» — это ключ в [RS_RunStats], тот, кто его пишет, и строка здесь;
## сам экран не меняется.
@tool
class_name RS_RunStatCatalog
extends Resource

## Порядок строк = порядок в сводке.
@export var rows: Array[RS_RunStatRow] = []

## Показывается, когда у показателя нечего показать, а прятать строку нельзя.
const EMPTY_TEXT := "—"


## Строки, которым в ЭТОЙ сводке есть что сказать.
func visible_rows(stats: RS_RunStats) -> Array[RS_RunStatRow]:
	var out: Array[RS_RunStatRow] = []
	if stats == null:
		return out
	for row: RS_RunStatRow in rows:
		if row == null or row.label_key == &"":
			continue
		if row.hide_when_empty and _is_empty(row, stats):
			continue
		out.append(row)
	return out


## Готовый текст значения для строки [param row]. Имена тел переводятся здесь —
## в записи забега лежит ключ, а не строка (см. RS_RunBody.name_key).
func value_text(row: RS_RunStatRow, stats: RS_RunStats) -> String:
	if row == null or stats == null:
		return EMPTY_TEXT
	match row.format:
		RS_RunStatRow.Format.TIME:
			return format_time(stats.value(row.key))
		RS_RunStatRow.Format.BODY_LIST:
			var names := PackedStringArray()
			for body: RS_RunBody in stats.bodies:
				if body == null:
					continue
				names.append(tr(body.name_key) if body.name_key != &"" else EMPTY_TEXT)
			return ", ".join(names) if not names.is_empty() else EMPTY_TEXT
		_:
			return str(int(roundf(stats.value(row.key))))


## ММ:СС — намеренно без слов «мин» и «с»: двоеточие читается на любом языке и
## не заводит ещё одну строку перевода на каждый показатель времени.
static func format_time(seconds: float) -> String:
	var total := int(maxf(seconds, 0.0))
	return "%d:%02d" % [total / 60, total % 60]


func _is_empty(row: RS_RunStatRow, stats: RS_RunStats) -> bool:
	if row.format == RS_RunStatRow.Format.BODY_LIST:
		return stats.bodies.is_empty()
	return is_zero_approx(stats.value(row.key))
