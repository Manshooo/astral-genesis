extends Node3D
## Стенд клипов: облик тела на подставке, и клип играется сам по себе — без дерева, переходов и
## S_BodyAnimation. Время ведёт стенд (пауза, перемотка, покадрово, скорость, петля), AnimationPlayer стоит в ручном
## режиме и только применяет позу. Облик и клипы берутся у сцены тела, поэтому стенд годится любому анимированному телу.
## Вики: [[Полигон]].

const ClipSources := preload("res://dev/polygon/clip_sources.gd")

enum Model { BODY }

## Тело, чьи облик и клипы на стенде.
@export var body_scene: PackedScene

## Источники клипов полигона (dev/polygon/clip_sources.gd): основные и версии.
var clips: ClipSources
var model := Model.BODY
var clip: StringName = &""
var time := 0.0
var playing := true
var speed := 1.0
var loop := true
var springs := true
## Выбранная версия библиотеки текущего облика; "" — основная.
var variant_path := ""
## A/B: показана основная вместо выбранной версии, позиция клипа та же.
var showing_official := false

## Облик → { "node": Node3D, "key": StringName — ключ библиотеки, "official": String — путь основной }.
var _models: Dictionary = {}

@onready var _slot: Node3D = %Slot
@onready var _player: AnimationPlayer = %StandPlayer
@onready var focus: Marker3D = %Focus


func setup(sources: ClipSources) -> void:
	clips = sources
	clips.changed.connect(_refresh)
	_models[Model.BODY] = _take(body_scene, Vector3.ZERO)
	select_model(Model.BODY)


func select_model(which: Model) -> void:
	model = which
	for key in _models:
		(_models[key].node as Node3D).visible = key == which
	variant_path = ""
	showing_official = false
	var names := clip_names()
	clip = &"idle" if names.has("idle") else (StringName(names[0]) if not names.is_empty() else &"")
	time = 0.0
	_refresh()
	focus.global_position = _center(_models[which].node)


func select_clip(name: StringName) -> void:
	clip = name
	time = 0.0
	_refresh()


## Версия библиотеки текущего облика ("" — основная).
func select_variant(path: String) -> void:
	variant_path = path
	showing_official = false
	_refresh()


func toggle_ab() -> void:
	if variant_path == "":
		return
	showing_official = not showing_official
	_refresh()


## Версии, которые подходят к библиотеке текущего облика.
func variants() -> Array[Dictionary]:
	return clips.variants_of(_models[model].official)


## Клипы библиотеки, которая сейчас на облике, по алфавиту.
func clip_names() -> PackedStringArray:
	var names := PackedStringArray()
	var library := _library()
	if library != null:
		for name in library.get_animation_list():
			names.append(name)
	names.sort()
	return names


## Клипы, которые взяты из версии, а не из основной.
func overridden() -> PackedStringArray:
	var library := _library()
	return library.get_meta(ClipSources.META_OVERRIDDEN, PackedStringArray()) if library != null else PackedStringArray()


func length() -> float:
	var animation := _animation()
	return animation.length if animation != null else 0.0


## Шаг кадра клипа: клипы выгружены с частотой Blender-сцены, кадр — это Animation.step.
func frame_step() -> float:
	var animation := _animation()
	return animation.step if animation != null and animation.step > 0.0 else 1.0 / 30.0


func is_looping_clip() -> bool:
	var animation := _animation()
	return animation != null and animation.loop_mode != Animation.LOOP_NONE


func seek(at: float) -> void:
	time = clampf(at, 0.0, length())
	_apply()


## Пуск и пауза — кнопка и пробел экрана. Доигранный до конца клип пускается с начала.
func toggle_play() -> void:
	if not playing and time >= length():
		time = 0.0
	playing = not playing
	_apply()


## Кадр вперёд или назад; ставит на паузу — покадрово смотрят стоп-кадром.
func step(frames: int) -> void:
	playing = false
	var total := length()
	if total <= 0.0:
		return
	time = fposmod(time + frames * frame_step(), total) if loop else clampf(time + frames * frame_step(), 0.0, total)
	_apply()


func set_springs(on: bool) -> void:
	springs = on
	for spring: SpringBoneSimulator3D in _slot.find_children("*", "SpringBoneSimulator3D", true, false):
		spring.active = on


func _process(delta: float) -> void:
	if not playing or clip == &"":
		return
	var total := length()
	if total <= 0.0:
		return
	time += delta * speed
	if time > total:
		if loop:
			time = fposmod(time, total)
		else:
			time = total
			playing = false
	_apply()


## Облик, которым анимирует дерево сцены [param scene], — переносится на подставку, остальное (сущность, дерево)
## выбрасывается. Сцену тела целиком на стенд ставить нельзя: E_Body в _ready роняет облик рэгдоллом.
func _take(scene: PackedScene, lift: Vector3) -> Dictionary:
	var probe := scene.instantiate()
	var tree := RS_EntityVisuals.animation_tree(probe)
	var animated := tree.get_node(tree.root_node) as Node3D
	var key: StringName = tree.get_animation_library_list()[0]
	var official: String = clips.official_path_of(tree.get_animation_library(key))
	var placement := animated.transform
	animated.get_parent().remove_child(animated)
	probe.free()
	RS_EntityVisuals.strip_ragdoll(animated)
	_slot.add_child(animated)
	animated.transform = Transform3D(placement.basis, placement.origin + lift)
	return {"node": animated, "key": key, "official": official}


func _library() -> AnimationLibrary:
	if not _models.has(model) or clips == null:
		return null
	var official: String = _models[model].official
	if official == "" or not clips.officials.has(official):
		return null
	if variant_path == "" or showing_official:
		return clips.officials[official]
	return clips.merged(official, variant_path)


func _animation() -> Animation:
	var library := _library()
	return library.get_animation(clip) if library != null and library.has_animation(clip) else null


## Пересобирает плеер под облик, библиотеку и клип; позиция клипа сохраняется — на ней держится A/B.
func _refresh() -> void:
	if not _models.has(model):
		return
	for key in _player.get_animation_library_list():
		_player.remove_animation_library(key)
	var library := _library()
	if library == null:
		return
	var key: StringName = _models[model].key
	_player.add_animation_library(key, library)
	_player.root_node = _player.get_path_to(_models[model].node)
	if not library.has_animation(clip):
		return
	_player.play(StringName("%s/%s" % [key, clip]))
	time = minf(time, length())
	set_springs(springs)
	_apply()


## Клип без петли плеер, доиграв, останавливает сам, и current_animation становится пустым. Время ведёт стенд, а
## seek() поставит позу и остановленному плееру, поэтому опора — назначенный клип, а не «играет ли».
func _apply() -> void:
	if _player.assigned_animation != "":
		_player.seek(time, true)


## Середина облика по его мешам — точка, вокруг которой летает камера.
func _center(node: Node3D) -> Vector3:
	var box := AABB()
	var first := true
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var piece := mesh.global_transform * mesh.get_aabb()
		box = piece if first else box.merge(piece)
		first = false
	return box.get_center() if not first else node.global_position
