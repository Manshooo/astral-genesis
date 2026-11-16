## Симуляция рэгдоллов прямо в редакторе: физика редактора включается на время, рэгдоллы падают из своей позы,
## а по остановке поза ложится в кости Skeleton3D одним шагом истории — Ctrl+Z возвращает прежнюю.
## [[Редакторские инструменты]], «Симуляция рэгдолла».
@tool
extends RefCounted

enum Scope { SELECTED, ALL }

## Сдвиг кости меньше этого — шум физики, в сцену не пишется.
const EPSILON := 0.0001


## Один рэгдолл: его поза до пуска и последняя снятая с симулятора.
class _Ragdoll:
	extends RefCounted

	var simulator: PhysicalBoneSimulator3D
	var skeleton: Skeleton3D
	var was_active := true
	var before_position: Array[Vector3] = []
	var before_rotation: Array[Quaternion] = []
	var after_position: Array[Vector3] = []
	var after_rotation: Array[Quaternion] = []

	func _init(p_simulator: PhysicalBoneSimulator3D) -> void:
		simulator = p_simulator
		skeleton = p_simulator.get_skeleton()
		_read(before_position, before_rotation)

	## Зовётся из modification_processed: только там видна поза ПОСЛЕ симулятора — дальше Skeleton3D
	## возвращает кости к хранимой позе, и get_bone_pose в _process показал бы позу до пуска.
	func capture() -> void:
		_read(after_position, after_rotation)

	func _read(positions: Array[Vector3], rotations: Array[Quaternion]) -> void:
		positions.resize(skeleton.get_bone_count())
		rotations.resize(skeleton.get_bone_count())
		for bone in skeleton.get_bone_count():
			positions[bone] = skeleton.get_bone_pose_position(bone)
			rotations[bone] = skeleton.get_bone_pose_rotation(bone)


var _ragdolls: Array[_Ragdoll] = []
## Чужие RigidBody сцены на время симуляции заморожены: физика редактора включается для всего мира.
var _frozen: Array[RigidBody3D] = []


func is_running() -> bool:
	return not _ragdolls.is_empty()


## Запускает рэгдоллы сцены [param root]; возвращает, сколько их пошло.
func start(scope: Scope, root: Node, selection: Array[Node]) -> int:
	if is_running() or root == null:
		return 0
	for simulator in find(scope, root, selection):
		if simulator.get_skeleton() != null:
			_ragdolls.append(_Ragdoll.new(simulator))
	if _ragdolls.is_empty():
		return 0
	for body: RigidBody3D in root.find_children("*", "RigidBody3D", true, false):
		if not body.freeze:
			body.freeze = true
			_frozen.append(body)
	# В редакторе физический сервер выключен: без этого кости не сдвинутся ни на миллиметр.
	PhysicsServer3D.set_active(true)
	for ragdoll in _ragdolls:
		ragdoll.was_active = ragdoll.simulator.active
		ragdoll.simulator.active = true
		ragdoll.simulator.modification_processed.connect(ragdoll.capture)
		ragdoll.simulator.physical_bones_start_simulation()
	return _ragdolls.size()


## Останавливает симуляцию; [param commit] — записать позу в сцену шагом истории. Возвращает, сколько костей
## записано.
func stop(commit := true) -> int:
	if not is_running():
		return 0
	for ragdoll in _ragdolls:
		if not is_instance_valid(ragdoll.simulator):
			continue
		ragdoll.simulator.physical_bones_stop_simulation()
		ragdoll.simulator.modification_processed.disconnect(ragdoll.capture)
		ragdoll.simulator.active = ragdoll.was_active
	PhysicsServer3D.set_active(false)
	for body in _frozen:
		if is_instance_valid(body):
			body.freeze = false
	_frozen.clear()
	var written := _commit() if commit else 0
	_ragdolls.clear()
	return written


func _commit() -> int:
	var changes: Array = []
	for ragdoll in _ragdolls:
		if not is_instance_valid(ragdoll.skeleton) or ragdoll.after_position.is_empty():
			continue
		for bone in ragdoll.skeleton.get_bone_count():
			var moved := ragdoll.after_position[bone].distance_to(ragdoll.before_position[bone]) > EPSILON
			var turned := ragdoll.after_rotation[bone].angle_to(ragdoll.before_rotation[bone]) > EPSILON
			if moved or turned:
				changes.append([ragdoll, bone])
	if changes.is_empty():
		return 0
	var history := EditorInterface.get_editor_undo_redo()
	history.create_action("Симуляция рэгдолла")
	for change: Array in changes:
		var ragdoll: _Ragdoll = change[0]
		var bone: int = change[1]
		var position := "bones/%d/position" % bone
		var rotation := "bones/%d/rotation" % bone
		history.add_do_property(ragdoll.skeleton, position, ragdoll.after_position[bone])
		history.add_undo_property(ragdoll.skeleton, position, ragdoll.before_position[bone])
		history.add_do_property(ragdoll.skeleton, rotation, ragdoll.after_rotation[bone])
		history.add_undo_property(ragdoll.skeleton, rotation, ragdoll.before_rotation[bone])
	history.commit_action()
	return changes.size()


## Рэгдоллы для пуска. Выбранные: симуляторы внутри выделенного узла, а если их нет — тело, внутри которого
## выделенный узел (ближайший предок с ровно одним симулятором: подняться до общего родителя нескольких тел
## значило бы уронить чужие).
static func find(scope: Scope, root: Node, selection: Array[Node]) -> Array[PhysicalBoneSimulator3D]:
	var found: Array[PhysicalBoneSimulator3D] = []
	if scope == Scope.ALL:
		found = _ragdolls_in(root)
		return found
	for node in selection:
		var inside := _ragdolls_in(node)
		var parent := node.get_parent()
		while inside.is_empty() and parent != null and parent != root.get_parent():
			var around := _ragdolls_in(parent)
			if around.size() == 1:
				inside = around
			elif around.size() > 1:
				break
			parent = parent.get_parent()
		for simulator in inside:
			if not found.has(simulator):
				found.append(simulator)
	return found


## Только симуляторы с костями: редактор вешает на каждый Skeleton3D свой внутренний @PhysicalBoneSimulator3D
## без владельца и без PhysicalBone3D — запуск его рядом с настоящим дрался бы за тот же скелет.
static func _ragdolls_in(node: Node) -> Array[PhysicalBoneSimulator3D]:
	var candidates := node.find_children("*", "PhysicalBoneSimulator3D", true, false)
	if node is PhysicalBoneSimulator3D:
		candidates.append(node)
	var result: Array[PhysicalBoneSimulator3D] = []
	for simulator: PhysicalBoneSimulator3D in candidates:
		if simulator.get_children().any(func(child: Node) -> bool: return child is PhysicalBone3D):
			result.append(simulator)
	return result
