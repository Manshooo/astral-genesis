## res://src/resources/run_stats/rs_run_stat_catalog.gd
## Из чего складывается сводка забега (data/run_stat_catalog.tres): показатели и порядок. Экран итогов не знает показателей по имени — идёт по каталогу.
@tool
class_name RS_RunStatCatalog
extends Resource

## Порядок строк = порядок в сводке.
@export var rows: Array[RS_RunStatRow] = []

## Когда показывать нечего, а прятать строку нельзя.
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


## Текст значения строки; имена тел переводятся здесь (в записи — ключ).
func value_text(row: RS_RunStatRow, stats: RS_RunStats) -> String:
	if row == null or stats == null:
		return EMPTY_TEXT
	match row.format:
		RS_RunStatRow.Format.TIME:
			return format_time(stats.value(row.key))
		RS_RunStatRow.Format.BODY_LIST:
			# По видам с числом: список по телу рос и выталкивал кнопку «Возродиться» за край экрана.
			var counts: Dictionary[String, int] = {}
			for body: RS_RunBody in stats.bodies:
				if body == null:
					continue
				var body_name := tr(body.name_key) if body.name_key != &"" else EMPTY_TEXT
				counts[body_name] = counts.get(body_name, 0) + 1
			var names := PackedStringArray()
			for body_name: String in counts:
				names.append(body_name if counts[body_name] == 1 else tr("RUN_STAT_BODY_COUNT") % [body_name, counts[body_name]])
			return ", ".join(names) if not names.is_empty() else EMPTY_TEXT
		_:
			return str(int(roundf(stats.value(row.key))))


## ММ:СС без слов «мин» и «с»: двоеточие читается на любом языке.
static func format_time(seconds: float) -> String:
	var total := int(maxf(seconds, 0.0))
	# Минуты — именно целая часть, секунды берутся отдельно через остаток.
	@warning_ignore("integer_division")
	return "%d:%02d" % [total / 60, total % 60]


func _is_empty(row: RS_RunStatRow, stats: RS_RunStats) -> bool:
	if row.format == RS_RunStatRow.Format.BODY_LIST:
		return stats.bodies.is_empty()
	return is_zero_approx(stats.value(row.key))
