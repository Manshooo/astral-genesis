extends Control
## Экран беговой дорожки: скорость манекена, удар, попадание, прыжок, безделье и гибель — а что из этого сыграть, решает
## S_BodyAnimation, как в забеге. Показывает её решение рядом с тем, что играет дерево, — переход и смешивание видны
## расхождением этих строк. Темп времени и версия клипов — общие для полигона. Вики: [[Полигон]].

const Polygon := preload("res://dev/polygon/polygon.gd")

const VIEW_DISTANCE := 9.0
## Высота точки взгляда над подошвой манекена, м.
const VIEW_HEIGHT := 1.2

var _treadmill: Node3D
var _polygon: Node
## Путь основной библиотеки тела манекена — её версии в списке «Клипы».
var _official := ""

@onready var _camera: Camera3D = %OrbitCamera
@onready var _status: Label = %Status
@onready var _speed: HSlider = %Speed
@onready var _speed_label: Label = %SpeedLabel
@onready var _presets: HBoxContainer = %Presets
@onready var _fidgets: HBoxContainer = %Fidgets
@onready var _time_scales: HBoxContainer = %TimeScales
@onready var _source_pick: OptionButton = %SourcePick
@onready var _follow: CheckBox = %Follow


func setup(treadmill: Node3D, polygon: Node) -> void:
	_treadmill = treadmill
	_polygon = polygon
	_camera.look_at_target(treadmill, VIEW_DISTANCE, VIEW_HEIGHT)
	_speed.set_value_no_signal(treadmill.speed)
	_speed.value_changed.connect(func(value: float) -> void: _treadmill.speed = value)
	(%Jump as Button).pressed.connect(_treadmill.jump)
	(%Bite as Button).pressed.connect(_treadmill.bite)
	(%Hit as Button).pressed.connect(_treadmill.hit)
	(%Death as Button).pressed.connect(_treadmill.kill)
	(%Fidget as Button).pressed.connect(_treadmill.fidget)
	(%Respawn as Button).pressed.connect(_respawn)
	_follow.toggled.connect(func(_on: bool) -> void: _retarget())
	_source_pick.item_selected.connect(_on_source)
	_fill_presets()
	var tree: AnimationTree = treadmill.animation_tree()
	var fidgets := S_BodyAnimation.fidgets_of(tree) if tree != null else PackedStringArray()
	_fill_buttons(_fidgets, Array(fidgets), func(i: int) -> void: _treadmill.fidget_kind(StringName(fidgets[i])))
	_fill_buttons(_time_scales, Polygon.TIME_SCALES.map(func(value: float) -> String: return "×%s" % value),
		func(i: int) -> void: _polygon.set_time_scale(Polygon.TIME_SCALES[i]))
	_fill_sources()


func _process(_delta: float) -> void:
	if _treadmill == null:
		return
	_speed_label.text = "%.1f м/с" % _treadmill.speed
	var lines := PackedStringArray()
	var status: Dictionary = _treadmill.status()
	for key in status:
		lines.append("%s: %s" % [key, status[key]])
	lines.append("темп времени: ×%s" % Engine.time_scale)
	_status.text = "\n".join(lines)
	if _camera.target != _wanted_target():
		_retarget()


func _retarget() -> void:
	_camera.target = _wanted_target()


## За манекеном, пока он жив; после гибели — за его трупом; без слежения — центр дорожки.
func _wanted_target() -> Node3D:
	if not _follow.button_pressed:
		return _treadmill
	for candidate in [_treadmill.puppet, _treadmill.corpse]:
		if is_instance_valid(candidate):
			return candidate
	return _treadmill


func _respawn() -> void:
	_treadmill.spawn_puppet()
	_treadmill.speed = _speed.value
	_retarget()
	_fill_sources()


## Кнопки скоростей — по клипам хода тела (treadmill.presets), а не числами здесь.
func _fill_presets() -> void:
	var presets: Dictionary = _treadmill.presets()
	var names := presets.keys()
	_fill_buttons(_presets, names, func(i: int) -> void: _speed.value = presets[names[i]])


func _fill_sources() -> void:
	var tree: AnimationTree = _treadmill.animation_tree()
	_source_pick.clear()
	_source_pick.add_item("основные")
	_official = ""
	if tree != null and not tree.get_animation_library_list().is_empty():
		_official = _polygon.clips.official_path_of(tree.get_animation_library(tree.get_animation_library_list()[0]))
	var versions: Array[Dictionary] = _polygon.clips.variants_of(_official) if _official != "" else []
	for version in versions:
		_source_pick.add_item(version.title)
		if _polygon.clips.chosen.get(_official, "") == version.path:
			_source_pick.selected = _source_pick.item_count - 1
	_source_pick.disabled = versions.is_empty()


## Версия ставится всем деревьям полигона, не только манекену: и трупу, и надетому облику.
func _on_source(index: int) -> void:
	if _official == "":
		return
	var versions: Array[Dictionary] = _polygon.clips.variants_of(_official)
	_polygon.clips.choose(_official, "" if index == 0 else versions[index - 1].path)


## Кнопки ряда [param row] по подписям: первая — образец из сцены, остальные — его копии (как в меню отладки).
func _fill_buttons(row: HBoxContainer, titles: Array, on_press: Callable) -> void:
	var template := row.get_child(0) as Button
	for i in titles.size():
		var button := template if i == 0 else template.duplicate() as Button
		if i > 0:
			row.add_child(button)
		button.text = titles[i]
		button.pressed.connect(on_press.bind(i))
	template.visible = not titles.is_empty()
