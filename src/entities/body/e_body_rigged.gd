@tool
extends E_Body
## Тело на своём .glb (hound, L5, учёный): облик SK_* со скелетом, рэгдоллом и деревом клипов. Тело в комнате лежит
## рэгдоллом с начала (клипа «без сознания» нет); свежий труп (dying) падает клипом гибели, а в конце его подхватывает
## рэгдолл. Вики: [[Захват тела]].


func _ready() -> void:
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
	# Связь через сигнал, не await: труп могут снести вместе с комнатой до конца клипа.
	get_tree().create_timer(length).timeout.connect(_lie_down)


func _lie_down() -> void:
	RS_EntityVisuals.animation_tree(self).active = false
	# Пружины качали бы хвост поверх рэгдолла.
	for spring in find_children("*", "SpringBoneSimulator3D", true, false):
		(spring as SpringBoneSimulator3D).active = false
	for simulator in find_children("*", "PhysicalBoneSimulator3D", true, false):
		(simulator as PhysicalBoneSimulator3D).physical_bones_start_simulation()
