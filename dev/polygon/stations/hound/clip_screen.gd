extends Control
## Экран стенда клипов: выбор облика, версии и клипа, время клипа и скорость, A/B между основной и версией. Сам ничего
## не проигрывает — правит стенд (clip_stand.gd) и показывает его состояние. Вики: [[Полигон]].

## С какого расстояния камера смотрит на облик.
const VIEW_DISTANCE := 4.5

var _stand: Node3D
## Строки списка клипов → имя клипа (подпись несёт пометку версии).
var _clip_rows: Array[StringName] = []

@onready var _camera: Camera3D = %OrbitCamera
@onready var _model_pick: OptionButton = %ModelPick
@onready var _source_pick: OptionButton = %SourcePick
@onready var _ab: Button = %AbButton
@onready var _clips: ItemList = %Clips
@onready var _time: HSlider = %TimeSlider
@onready var _time_label: Label = %TimeLabel
@onready var _play: Button = %Play
@onready var _loop: CheckBox = %Loop
@onready var _speed: HSlider = %Speed
@onready var _speed_label: Label = %SpeedLabel
@onready var _springs: CheckBox = %Springs


func setup(stand: Node3D, _polygon: Node) -> void:
	_stand = stand
	_camera.look_at_target(stand.focus, VIEW_DISTANCE)
	_model_pick.set_item_disabled(1, not stand.has_arms())
	_model_pick.selected = stand.model
	_loop.button_pressed = stand.loop
	_speed.set_value_no_signal(stand.speed)
	_springs.button_pressed = stand.springs

	_model_pick.item_selected.connect(_on_model)
	_source_pick.item_selected.connect(_on_source)
	_ab.pressed.connect(_toggle_ab)
	_clips.item_selected.connect(func(row: int) -> void: _stand.select_clip(_clip_rows[row]))
	_time.value_changed.connect(_stand.seek)
	_time.drag_started.connect(func() -> void: _stand.playing = false)
	_play.pressed.connect(_toggle_play)
	(%Back as Button).pressed.connect(_stand.step.bind(-1))
	(%Forward as Button).pressed.connect(_stand.step.bind(1))
	_loop.toggled.connect(func(on: bool) -> void: _stand.loop = on)
	_speed.value_changed.connect(func(value: float) -> void: _stand.speed = value)
	_springs.toggled.connect(_stand.set_springs)
	_stand.clips.changed.connect(_fill)
	_fill()


func _process(_delta: float) -> void:
	if _stand == null:
		return
	var total: float = _stand.length()
	_time.max_value = maxf(total, 0.001)
	_time.step = _stand.frame_step() * 0.25
	_time.set_value_no_signal(_stand.time)
	var frame := roundi(_stand.time / _stand.frame_step())
	var frames := roundi(total / _stand.frame_step())
	_time_label.text = "%.3f / %.3f с · кадр %d / %d%s" % [_stand.time, total, frame, frames,
		" · клип зациклен" if _stand.is_looping_clip() else ""]
	_play.text = "Пауза" if _stand.playing else "Пуск"
	_speed_label.text = "×%.2f" % _stand.speed
	if _stand.variant_path == "":
		_ab.text = "A/B — выберите версию"
	else:
		_ab.text = "Сейчас: %s (Tab — сменить)" % ("основные" if _stand.showing_official else "версия")
	_ab.disabled = _stand.variant_path == ""


## Клавиши стенда; кнопки экрана фокуса не берут, так что пробел и стрелки не «нажимают» последнюю кликнутую.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	match key.keycode:
		KEY_SPACE:
			if not key.echo:
				_toggle_play()
		KEY_LEFT:
			_stand.step(-1)
		KEY_RIGHT:
			_stand.step(1)
		KEY_UP, KEY_DOWN:
			_next_clip(-1 if key.keycode == KEY_UP else 1)
		KEY_TAB:
			if not key.echo:
				_toggle_ab()
		_:
			return
	get_viewport().set_input_as_handled()


## Пометки «из версии» в списке верны только для показанной стороны — список перерисовывается.
func _toggle_ab() -> void:
	_stand.toggle_ab()
	_fill()


func _toggle_play() -> void:
	_stand.toggle_play()


func _next_clip(direction: int) -> void:
	if _clip_rows.is_empty():
		return
	var row := wrapi(_clip_rows.find(_stand.clip) + direction, 0, _clip_rows.size())
	_clips.select(row)
	_stand.select_clip(_clip_rows[row])


func _on_model(index: int) -> void:
	_stand.select_model(index)
	_camera.look_at_target(_stand.focus, VIEW_DISTANCE if index == 0 else VIEW_DISTANCE * 0.5)
	_fill()


func _on_source(index: int) -> void:
	var versions: Array[Dictionary] = _stand.variants()
	_stand.select_variant("" if index == 0 else versions[index - 1].path)
	_fill()


## Версии и клипы текущего облика. Клип из версии помечен: A/B на нём показывает разницу, на остальных — одно и то же.
func _fill() -> void:
	_source_pick.clear()
	_source_pick.add_item("основные")
	var versions: Array[Dictionary] = _stand.variants()
	for version in versions:
		_source_pick.add_item(version.title)
		if version.path == _stand.variant_path:
			_source_pick.selected = _source_pick.item_count - 1
	_source_pick.disabled = versions.is_empty()
	if _stand.variant_path == "":
		_source_pick.selected = 0

	_clips.clear()
	_clip_rows.clear()
	var from_version: PackedStringArray = _stand.overridden() if not _stand.showing_official else PackedStringArray()
	for clip_name in _stand.clip_names():
		_clips.add_item("%s%s" % [clip_name, "   · версия" if from_version.has(clip_name) else ""])
		_clip_rows.append(StringName(clip_name))
	var at := _clip_rows.find(_stand.clip)
	if at >= 0:
		_clips.select(at)
