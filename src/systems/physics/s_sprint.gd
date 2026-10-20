# res://src/systems/physics/s_sprint.gd
# Группа "physics". Бег — по одной возможности одна система. СВОЕЙ АРИФМЕТИКИ СКОРОСТИ НЕТ: кладёт в C_StatModifiers источник &"sprint" с множителем к WALK_SPEED, а S_Walk читает
# посчитанный стат — перк на ходьбу ускоряет и бег (отвергнуто: ветка `if sprinting` в S_Walk). Источник ставится и снимается ПО ФРОНТУ (C_Sprint.active), не каждый кадр. Вторая выборка — тем,
# у кого бега НЕТ: модификатор лежит в C_StatModifiers души и переживает пересадку (бегал бы вечно), и защёлку нажатия надо гасить, как у S_Jump.
class_name S_Sprint
extends System

## Имя источника, отдельное от &"skills": источник снимается целиком — не мешать нажатую клавишу с перками.
const SOURCE := &"sprint"


func sub_systems() -> Array[Array]:
	return [
		[q.with_all([C_PlayerInput, C_Sprint, C_StatModifiers]), _sprint],
		[q.with_all([C_PlayerInput, C_StatModifiers]).with_none([C_Sprint]), _swallow],
	]


## Строго ДО хода: S_Walk читает посчитанный стат, иначе кадр опоздания на каждое нажатие.
func deps() -> Dictionary[int, Array]:
	return {Runs.Before: [S_Walk]}


func _sprint(entities: Array[Entity], _components: Array, _delta: float) -> void:
	for entity in entities:
		var inp := entity.get_component(C_PlayerInput) as C_PlayerInput
		inp.sprint_pressed = false  # бежать можем — отвечать на нажатие нечего

		var sprint := entity.get_component(C_Sprint) as C_Sprint
		if sprint.active == inp.sprint_held:
			continue  # состояние не менялось — свёртку не трогаем

		sprint.active = inp.sprint_held
		var mods := entity.get_component(C_StatModifiers) as C_StatModifiers
		if sprint.active:
			# Множитель тела — тоже стат: «бегай быстрее» в любом теле — перк.
			var factor := C_StatModifiers.of(
				entity, C_StatModifiers.SPRINT_MULTIPLIER, sprint.speed_multiplier
			)
			mods.set_source(SOURCE, {}, {C_StatModifiers.WALK_SPEED: factor})
		else:
			mods.clear_source(SOURCE)


## Бежать нечем — снимаем чужой множитель и гасим защёлку. clear_source идемпотентен: звать каждый кадр дешевле наблюдателя (тело уходит тремя путями: захват, выход, догоревшее время).
func _swallow(entities: Array[Entity], _components: Array, _delta: float) -> void:
	for entity in entities:
		var mods := entity.get_component(C_StatModifiers) as C_StatModifiers
		mods.clear_source(SOURCE)

		var inp := entity.get_component(C_PlayerInput) as C_PlayerInput
		if not inp.sprint_pressed:
			continue
		inp.sprint_pressed = false

		# Сообщаем, только если игрок ВО ПЛОТИ — как S_Jump.
		if entity.has_component(C_Embodied):
			C_ScreenMessage.show_on(entity, "HUD_MSG_NO_SPRINT", cmd)
