# res://src/systems/physics/s_jump.gd
# Группа: "physics". Прыжок — по одной возможности одна система.
#
# Тело без C_Jump в основную выборку не попадает, и знать о безногих телах этой
# системе не нужно: возможности нет — прыжка нет. Раньше это была ветка внутри
# S_PlayerMovement, и каждое новое тело добавляло бы туда условий.
#
# ВТОРАЯ ВЫБОРКА — про тех, у кого прыжка НЕТ, и она здесь не для симметрии.
# C_PlayerInput.jump_pressed — защёлка: её взводит E_Player._input, а гасит тот,
# кто её съел. Если гасить только в ветке прыжка, нажатие, сделанное призраком
# или безногим телом, сработало бы в тот самый миг, когда игрок вселится в
# прыгучее тело. Держать обе половины защёлки в одном файле — единственный способ
# не разъехаться: разнеси их по системам, и «кто гасит» станет вопросом порядка.
class_name S_Jump
extends System


func sub_systems() -> Array[Array]:
	return [
		[q.with_all([C_PlayerInput, C_Velocity, C_Jump]), _jump],
		[q.with_all([C_PlayerInput]).with_none([C_Jump]), _swallow],
	]


## Прыгать умеем — прыгаем, если стоим на полу.
##
## Высота — из C_Jump этого тела, пропущенная через модификаторы души: база
## принадлежит телу, «+20% к прыжку» — перку, и складывать их должен один
## C_StatModifiers.of, а не правка этой формулы.
func _jump(entities: Array[Entity], _components: Array, _delta: float) -> void:
	for entity in entities:
		var inp := entity.get_component(C_PlayerInput) as C_PlayerInput
		if not inp.jump_pressed:
			continue
		inp.jump_pressed = false

		var body := entity as Node as CharacterBody3D
		if body == null or not body.is_on_floor():
			continue
		var jump := entity.get_component(C_Jump) as C_Jump
		var vel := entity.get_component(C_Velocity) as C_Velocity
		vel.velocity.y = C_StatModifiers.of(entity, C_StatModifiers.JUMP_VELOCITY, jump.velocity)


## Прыгать нечем — гасим защёлку, чтобы нажатие не «дожило» до следующего тела.
##
## Сообщаем игроку, только если он ВО ПЛОТИ: у безногого тела «нечем прыгать» —
## содержательная причина отказа, ровно как «Нужно тело» у интерактивов
## (hud_prompt.gd). Развоплощённому сообщать нечего — по «Управлению» подниматься
## взглядом это ЗАДУМАННОЕ поведение, а не урезанная возможность, и текст про
## «тело» был бы враньём: тела у него как раз и нет.
func _swallow(entities: Array[Entity], _components: Array, _delta: float) -> void:
	for entity in entities:
		var inp := entity.get_component(C_PlayerInput) as C_PlayerInput
		if not inp.jump_pressed:
			continue
		inp.jump_pressed = false

		if entity.has_component(C_Embodied):
			_notify(entity, "Этому телу нечем прыгать")


## Короткая строка поверх HUD. Через буфер и remove+add — как S_BodySnatch._notify:
## прямая запись в поля C_ScreenMessage сигналов миру не шлёт, и HUD не увидел бы
## новый текст.
func _notify(entity: Entity, text: String) -> void:
	if entity.has_component(C_ScreenMessage):
		cmd.remove_component(entity, C_ScreenMessage)
	var message := C_ScreenMessage.new()
	message.text = text
	cmd.add_component(entity, message)
