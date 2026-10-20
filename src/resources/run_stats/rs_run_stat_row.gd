## res://src/resources/run_stats/rs_run_stat_row.gd
## Строка сводки забега: показатель, подпись, вид. ДАННЫЕ, а не узел экрана — новый показатель стоит строки в data/run_stat_catalog.tres.
@tool
class_name RS_RunStatRow
extends Resource

## Вид показателя: список тел значением не является, но живёт такой же строкой.
enum Format {
	NUMBER,  ## целое: комнаты, тела, урон, очки
	TIME,  ## секунды забега как ММ:СС
	BODY_LIST,  ## перечисление занятых тел по именам
}

## Ключ показателя из RS_RunStats; для BODY_LIST не используется.
@export var key: StringName = &""

## Ключ ПЕРЕВОДА подписи (ui.csv).
@export var label_key: StringName = &""

@export var format: Format = Format.NUMBER

## Прятать строку, когда показывать нечего (урон, которого не было); время и комнаты честнее показать нулями.
@export var hide_when_empty: bool = true
