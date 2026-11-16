## Панель симуляции рэгдолла в меню 3D-вьюпорта: пуск/стоп и охват — выбранные тела или все в сцене.
## Логика — в ragdoll_sim.gd. [[Редакторские инструменты]], «Симуляция рэгдолла».
@tool
extends HBoxContainer

const RagdollSim := preload("res://addons/game_design_tool/ragdoll/ragdoll_sim.gd")

var _sim := RagdollSim.new()

@onready var _toggle: Button = %Simulate
@onready var _scope: OptionButton = %Scope
@onready var _status: Label = %Status


func _ready() -> void:
	_toggle.toggled.connect(_on_toggled)


## Остановить с записью позы: перед сохранением сцены и при смене вкладки — иначе в файл попала бы заморозка
## чужих тел, а поза осталась бы в воздухе.
func stop() -> void:
	if not _sim.is_running():
		return
	_toggle.set_pressed_no_signal(false)
	_report(_sim.stop(true))


## Остановить без записи — плагин выгружается.
func cancel() -> void:
	_sim.stop(false)
	_toggle.set_pressed_no_signal(false)


func _on_toggled(on: bool) -> void:
	if not on:
		_report(_sim.stop(true))
		return
	var selection: Array[Node] = EditorInterface.get_selection().get_top_selected_nodes()
	var count := _sim.start(_scope.selected as RagdollSim.Scope, EditorInterface.get_edited_scene_root(), selection)
	if count == 0:
		_toggle.set_pressed_no_signal(false)
		_status.text = "Нет рэгдоллов" if _scope.selected == RagdollSim.Scope.ALL else "Выделите узел внутри тела"
		return
	_status.text = "Падают: %d" % count


func _report(written: int) -> void:
	_status.text = "Записано костей: %d (Ctrl+Z — назад)" % written if written > 0 else "Поза не изменилась"
