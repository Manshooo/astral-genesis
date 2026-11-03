@tool
extends E_Body
## Тело-«гончая»: ростовая фигура с собачьей головой, ~1.8 м, облик SK_hound. Тело в комнате лежит рэгдоллом с начала
## (клипа «без сознания» нет); труп только что убитой гончей (dying) падает клипом гибели, а рэгдолл подхватывает его в конце.


func _ready() -> void:
	# E_Body — @tool, _ready() срабатывает и в редакторе: без отсечки Jolt роняет риг под гравитацией и поза костей сохраняется в файл.
	if Engine.is_editor_hint():
		return
	if dying:
		_fall()
	else:
		_lie_down()


func _fall() -> void:
	var tree := RS_EntityVisuals.animation_tree(self)
	tree.active = true
	(tree.get(S_BodyAnimation.STATE) as AnimationNodeStateMachinePlayback).start(S_BodyAnimation.DEATH)
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
