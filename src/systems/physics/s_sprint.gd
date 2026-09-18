# res://src/systems/physics/s_sprint.gd
# Группа: "physics". Ускорение (бег) — по одной возможности одна система.
#
# СВОЕЙ АРИФМЕТИКИ СКОРОСТИ ЗДЕСЬ НЕТ, и это главное решение. Бег не считает,
# с какой скоростью идти, и S_Walk ничего не знает про бег: система кладёт в
# C_StatModifiers источник &"sprint" с множителем к WALK_SPEED, а ход, как и
# раньше, читает ПОСЧИТАННЫЙ стат. Отсюда бесплатно следует то, ради чего слой
# модификаторов и заводился: перк «+2 м/с к ходьбе» ускоряет и бег тоже, два
# источника складываются по общему правилу, а «сделать бег быстрее» правится
# данными, а не формулой.
#
# Отклонённая альтернатива — ветка `if sprinting` внутри S_Walk. Она дешевле на
# один файл и дороже всем остальным: ход перестал бы быть «одна возможность —
# одна система», а порядок «сначала перки, потом бег» пришлось бы держать в
# голове вместо того, чтобы получить его из свёртки (base + Σflat) * Πmult.
#
# ИСТОЧНИК СТАВИТСЯ И СНИМАЕТСЯ ПО ФРОНТУ, а не каждый кадр: set_source
# пересобирает словари и сворачивает все источники заново, и делать это 60 раз
# в секунду на удержанной клавише незачем. Память о прошлом кадре — C_Sprint.active.
#
# ВТОРАЯ ВЫБОРКА — про тех, у кого бега НЕТ, и она здесь не для симметрии, а по
# той же причине, что у S_Jump. Во-первых, источник &"sprint" обязан исчезнуть
# вместе с телом: развоплощение снимает C_Sprint с души (общий проход по
# C_BodyTrait в O_ExpelFromBody), но модификатор оно снять не может — он лежит
# в C_StatModifiers, который принадлежит душе и переживает любую пересадку.
# Останься он — призрак и следующее тело бегали бы вечно. Во-вторых, защёлку
# нажатия надо гасить и тому, кому бежать нечем, иначе нажатие, сделанное
# ползуном, сработало бы в тот миг, когда игрок пересядет в бегающее тело.
class_name S_Sprint
extends System

## Имя источника модификаторов. Своё, отдельное от &"skills": источник
## перезаписывается и снимается целиком, и мешать в него разово нажатую клавишу
## с перками дерева было бы способом снять перки вместе с бегом.
const SOURCE := &"sprint"


func sub_systems() -> Array[Array]:
	return [
		[q.with_all([C_PlayerInput, C_Sprint, C_StatModifiers]), _sprint],
		[q.with_all([C_PlayerInput, C_StatModifiers]).with_none([C_Sprint]), _swallow],
	]


## Строго ДО хода: S_Walk читает посчитанный стат, и обратный порядок отдавал бы
## бегу (и торможению) один кадр опоздания на каждое нажатие.
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
			# Множитель тела — тоже стат: «бегай ещё быстрее в любом теле»
			# обязано быть перком, а не правкой сцен всех тел разом.
			var factor := C_StatModifiers.of(
				entity, C_StatModifiers.SPRINT_MULTIPLIER, sprint.speed_multiplier
			)
			mods.set_source(SOURCE, {}, {C_StatModifiers.WALK_SPEED: factor})
		else:
			mods.clear_source(SOURCE)


## Бежать нечем — снимаем чужой множитель и гасим защёлку.
##
## clear_source идемпотентен (без источника выходит сразу), поэтому звать его
## каждый кадр дешевле, чем ловить момент развоплощения отдельным наблюдателем:
## тело у души появляется и исчезает тремя разными путями (захват, выход,
## догоревшее время), и наблюдатель на каждый из них разъехался бы молча.
func _swallow(entities: Array[Entity], _components: Array, _delta: float) -> void:
	for entity in entities:
		var mods := entity.get_component(C_StatModifiers) as C_StatModifiers
		mods.clear_source(SOURCE)

		var inp := entity.get_component(C_PlayerInput) as C_PlayerInput
		if not inp.sprint_pressed:
			continue
		inp.sprint_pressed = false

		# Сообщаем, только если игрок ВО ПЛОТИ — ровно как S_Jump: у тела «нечем
		# бежать» содержательная причина отказа, а призраку текст про тело был бы
		# враньём, тела у него как раз и нет.
		if entity.has_component(C_Embodied):
			_notify(entity, "Это тело не умеет бегать")


## Короткая строка поверх HUD. Через буфер и remove+add — как S_Jump._notify:
## прямая запись в поля C_ScreenMessage сигналов миру не шлёт, и HUD не увидел бы
## новый текст.
func _notify(entity: Entity, text: String) -> void:
	if entity.has_component(C_ScreenMessage):
		cmd.remove_component(entity, C_ScreenMessage)
	var message := C_ScreenMessage.new()
	message.text = text
	cmd.add_component(entity, message)
