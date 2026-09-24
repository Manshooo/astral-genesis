# res://dev/debug_menu.gd
## Меню отладки: читы, которые удобнее нажать мышью, чем держать клавишей, —
## начисление очков навыков и эссенции Архитектора и перенос в уникальные
## комнаты. Открывается из отладочного оверлея и живёт экраном в стеке
## UIManager: курсор, блок ввода игрока и закрытие по Esc — те же, что у дерева
## навыков, своих правил у меню нет.
##
## Почему меню, а не ещё клавиши. Ряд F-клавиш кончился: F5 занят встроенным
## ui_filedialog_refresh, а F9–F12 при запуске из редактора — его отладчик (точка
## останова, шаги, продолжить), и нажатие уходило редактору вместе с курсором.
## Клавиша на каждую уникальную комнату к тому же росла бы вместе с конфигом.
##
## Разделы — FoldableContainer в общей FoldableGroup, то есть аккордеон: раскрыт
## один раздел, остальные свёрнуты, и меню не растёт с каждым новым. Свернуть можно
## и все — allow_folding_all.
##
## Само меню ничего не начисляет и никуда не переносит: оно шлёт сигнал, а делает
## оверлей — у него же то, что работает и без меню, и подписи кнопок берутся из
## его таблиц. Кнопки из шаблонов в сцене, копии делает код — как строки
## шпаргалки оверлея.
extends Control

## Кнопку нажали; куда переносить и как это назвать — решает оверлей, у него же
## и сам перенос (тот, что без меню, по клавише, работает тем же путём).
signal travel_requested(scene_path: String, title: String)
## Нажата кнопка начисления — номер записи в таблице начислений оверлея.
signal grant_requested(index: int)

@onready var _grants: VBoxContainer = %Grants
@onready var _rooms: VBoxContainer = %Rooms


## [param rooms] — { "title": String, "scene_path": String } на каждую кнопку
## переноса; [param grants] — подписи кнопок начисления, по порядку таблицы.
func setup(rooms: Array[Dictionary], grants: Array[String]) -> void:
	var grant_buttons := _fill(_grants, grants.size())
	for i in grants.size():
		grant_buttons[i].text = grants[i]
		grant_buttons[i].pressed.connect(grant_requested.emit.bind(i))

	var room_buttons := _fill(_rooms, rooms.size())
	for i in rooms.size():
		var room := rooms[i]
		room_buttons[i].text = room["title"]
		room_buttons[i].pressed.connect(travel_requested.emit.bind(room["scene_path"], room["title"]))


## [param count] кнопок в разделе: первая — шаблон из сцены, остальные — его
## копии. Пустой список — не повод показывать кнопку-заглушку из сцены.
func _fill(section: VBoxContainer, count: int) -> Array[Button]:
	var template: Button = section.get_child(0)
	var buttons: Array[Button] = []
	for i in count:
		var button: Button = template if i == 0 else template.duplicate()
		if i > 0:
			section.add_child(button)
		buttons.append(button)
	template.visible = count > 0
	return buttons
