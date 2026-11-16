@tool
extends E_Body
## Тело на своём .glb (hound, L5, учёный): облик SK_* со скелетом, рэгдоллом и деревом клипов. Тело в комнате лежит
## рэгдоллом с начала (клипа «без сознания» нет); свежий труп (dying) начинает падать клипом гибели, а на его середине
## тело подхватывает рэгдолл со скоростью костей из клипа. Суставы рэгдолла ведёт S_Ragdoll (C_Ragdoll). Вики: [[Захват тела]].

## Два последних кадра клипа гибели: где были тела костей и когда — из разницы рэгдолл берёт скорость. Пара, а
## не «прошлый кадр против подхвата»: таймер подхвата может сработать в том же кадре, что и замер, и дать ноль.
var _bones: Array[PhysicalBone3D] = []
var _before: Dictionary[PhysicalBone3D, Vector3] = {}
var _before_usec := 0
var _last: Dictionary[PhysicalBone3D, Vector3] = {}
var _last_usec := 0


func _ready() -> void:
	# Замер клипа нужен только падающему трупу — и никогда в редакторе (скрипт @tool).
	set_process(false)
	# E_Body — @tool, _ready() срабатывает и в редакторе: без отсечки Jolt роняет риг под гравитацией и поза костей сохраняется в файл.
	if Engine.is_editor_hint():
		return
	super()
	if dying:
		_fall()
	else:
		_lie_down()


func _fall() -> void:
	var tree := RS_EntityVisuals.animation_tree(self)
	tree.active = true
	(tree.get(S_BodyAnimation.STATE) as AnimationNodeStateMachinePlayback).start(S_BodyAnimation.DEATH)
	# start() — лишь просьба до тика дерева; труп от S_Health встаёт отложенно, и в следующем кадре S_BodyAnimation
	# успевала раньше дерева увести его в idle. Нулевой шаг делает death текущим сразу.
	tree.advance(0.0)
	var length := 0.0
	for key in tree.get_animation_library_list():
		var library := tree.get_animation_library(key)
		if library.has_animation(S_BodyAnimation.DEATH):
			length = library.get_animation(S_BodyAnimation.DEATH).length
	var profile := C_Ragdoll.profile_of(self)
	var handover := profile.death_handover if profile != null else 1.0
	for node in find_children("*", "PhysicalBone3D", true, false):
		_bones.append(node as PhysicalBone3D)
	set_process(true)
	# Связь через сигнал, не await: труп могут снести вместе с комнатой до конца клипа.
	get_tree().create_timer(length * handover).timeout.connect(_lie_down)


## Пока играет клип гибели — где сейчас были бы тела костей.
func _process(_delta: float) -> void:
	_before = _last
	_before_usec = _last_usec
	_last = _bone_positions()
	_last_usec = Time.get_ticks_usec()


func _lie_down() -> void:
	set_process(false)
	var launch := _launch_velocities()
	RS_EntityVisuals.animation_tree(self).active = false
	# Пружины качали бы хвост поверх рэгдолла.
	for spring in find_children("*", "SpringBoneSimulator3D", true, false):
		(spring as SpringBoneSimulator3D).active = false
	var profile := C_Ragdoll.profile_of(self)
	if not dying and profile != null:
		# Лежащее с начала тело оседает из нейтральной позы, а не валится из позы покоя (T-поза) — дальше его ведёт S_Ragdoll.
		for skeleton in find_children("*", "Skeleton3D", true, false):
			profile.pose_skeleton(skeleton as Skeleton3D)
	var ragdoll := get_component(C_Ragdoll) as C_Ragdoll
	if ragdoll != null:
		ragdoll.launch = launch
	for simulator in find_children("*", "PhysicalBoneSimulator3D", true, false):
		(simulator as PhysicalBoneSimulator3D).physical_bones_start_simulation()


## Скорость тел костей в последнем кадре клипа: рэгдолл, подхвативший падение, продолжает его, а не стартует с места.
func _launch_velocities() -> Dictionary:
	var launch := {}
	var seconds := (_last_usec - _before_usec) / 1000000.0
	if _before.is_empty() or seconds <= 0.0:
		return launch
	var profile := C_Ragdoll.profile_of(self)
	var cap := profile.max_launch_speed if profile != null else 0.0
	for bone: PhysicalBone3D in _last:
		if _before.has(bone):
			launch[bone.bone_name] = ((_last[bone] - _before[bone]) / seconds).limit_length(cap)
	return launch


## Где тело кости стоит по позе скелета — там его поставит старт рэгдолла.
func _bone_positions() -> Dictionary[PhysicalBone3D, Vector3]:
	var out: Dictionary[PhysicalBone3D, Vector3] = {}
	for bone in _bones:
		var skeleton := bone.get_parent().get_parent() as Skeleton3D
		var id := bone.get_bone_id()
		if skeleton != null and id >= 0:
			out[bone] = (skeleton.global_transform * skeleton.get_bone_global_pose(id) * bone.body_offset).origin
	return out
