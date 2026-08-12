# res://src/systems/physics/s_player_movement.gd
# Группа: "physics". Считает желаемую скорость игрока в C_Velocity; применяет её
# S_Movement.
#
# Два режима, по наличию C_Embodied:
#   ВО ПЛОТИ — обычный шутерный ход: гравитация, прыжок, мгновенный старт/стоп.
#   РАЗВОПЛОЩЁН (БФЖ) — полёт: гравитации нет, направление берётся от КАМЕРЫ
#     (летим туда, куда смотрим), скорость набирается и гаснет через инерцию.
# Разделение именно тут, а не отдельной системой: обе ветки пишут в один
# C_Velocity, и держать их рядом дешевле, чем синхронизировать две системы.
#
# ЧИСЛА — не отсюда и не из настроек: во плоти их даёт надетое тело (C_Walk,
# C_Jump), развоплощённому — RS_GameConfig. Ветка «во плоти» уже читает
# возможности по НАЛИЧИЮ компонентов, так что разнос на S_Walk/S_Jump/S_Flight
# («Возможности тела и раскладка управления») — механическая работа, контент под
# неё уже готов.
class_name S_PlayerMovement
extends System

## Бит слоя permeable (layer_6): геометрия, СКВОЗЬ которую БФЖ проходит —
## решётки, тонкие перегородки. Что именно проницаемо, решает контент: достаточно
## положить коллайдер на этот слой вместо static_colliders. Несущие стены и полы
## остаются на static_colliders и твёрдые для всех, иначе призрак вылетал бы из
## комнаты в пустоту между ними и мимо всей структуры забега.
const PERMEABLE_BIT := 1 << 5


func query() -> QueryBuilder:
	return q.with_all([C_PlayerInput, C_Velocity]).iterate([C_PlayerInput, C_Velocity])

func process(entities: Array[Entity], components: Array, delta: float) -> void:
	var input_comps: Array = components[0]
	var velocity_comps: Array = components[1]

	for i in entities.size():
		var inp := input_comps[i] as C_PlayerInput
		var vel := velocity_comps[i] as C_Velocity
		var player := entities[i] as E_Player
		if player == null:
			continue

		var embodied := player.has_component(C_Embodied)
		_set_phasing(player, not embodied)
		if embodied:
			_move_embodied(player, inp, vel, delta)
		else:
			_move_ghost(player, inp, vel, delta)


## Включает/выключает проход сквозь проницаемую геометрию, убирая бит слоя из
## МАСКИ игрока. Ставим каждый кадр (с проверкой на изменение), а не по событию
## смены C_Embodied: забег начинается развоплощённым, то есть события «сняли
## тело» не будет вовсе, и наблюдатель оставил бы маску неверной до первого
## захвата.
func _set_phasing(player: E_Player, phasing: bool) -> void:
	var body := player as Node as CollisionObject3D
	if body == null:
		return
	var wanted := body.collision_mask & ~PERMEABLE_BIT if phasing else body.collision_mask | PERMEABLE_BIT
	if body.collision_mask != wanted:
		body.collision_mask = wanted


## Тело: гравитация, прыжок с пола, мгновенная смена направления.
##
## Скорость и прыжок берутся ЦЕЛИКОМ из характеристик надетого тела — C_Walk и
## C_Jump, абсолютные м/с. Никакой базы игрока, на которую они множились бы, нет:
## быстрое тело быстрое само по себе, а не «в 1.5 раза быстрее игрока».
## Пользовательские настройки (RS_Settings) — про мышь и экран, характеристики
## персонажа игрок не настраивает.
##
## Отсутствие компонента = отсутствие возможности: тело без C_Jump не прыгает,
## тело без C_Walk стоит на месте. Ветвления по «типу тела» тут нет и не будет —
## см. «Возможности тела и раскладка управления», где эти же компоненты
## разъедутся по отдельным системам (S_Walk/S_Jump), и тогда ветвление исчезнет
## совсем: тело просто не попадёт в выборку.
func _move_embodied(player: E_Player, inp: C_PlayerInput, vel: C_Velocity, delta: float) -> void:
	var walk := player.get_component(C_Walk) as C_Walk
	var jump := player.get_component(C_Jump) as C_Jump

	if not player.is_on_floor():
		vel.velocity.y -= GameConfig.config.gravity * delta
	else:
		vel.velocity.y = max(vel.velocity.y, 0.0)

	if inp.jump_pressed:
		if jump and player.is_on_floor():
			vel.velocity.y = jump.velocity
		inp.jump_pressed = false

	if walk and inp.move_direction != Vector3.ZERO:
		var wish = (player.transform.basis * inp.move_direction).normalized()
		vel.velocity.x = wish.x * walk.speed
		vel.velocity.z = wish.z * walk.speed
	else:
		vel.velocity.x = 0.0
		vel.velocity.z = 0.0


## БФЖ: бестелесное сознание не ходит, а плывёт. Его скорость — тоже абсолютное
## число, только живёт оно в RS_GameConfig: у призрака нет тела, которое дало бы
## ему C_Walk, а сам он один на всю игру.
##  - гравитации нет вовсе — никакого «падения» и опоры;
##  - направление считаем в базисе КАМЕРЫ, а не тела: смотришь вниз — летишь
##    вниз, и отдельные клавиши «вверх/вниз» не нужны;
##  - скорость не выставляется мгновенно, а подтягивается к желаемой (разгон) и
##    гаснет при отпущенных клавишах (инерция) — отсюда «плывущее» ощущение;
##  - ПРЫЖКА НЕТ: прыгать нечем, да и незачем при свободном полёте.
##
## То, что набор доступных действий зависит от состояния, — пока просто ветка
## if/else. Тел с разными возможностями (безногое тело не прыгает и т.п.) это
## уже не покроет — см. «Возможности тела и раскладка управления» в v0.5.0.
func _move_ghost(player: E_Player, inp: C_PlayerInput, vel: C_Velocity, delta: float) -> void:
	var gc := GameConfig.config
	var speed := gc.ghost_speed

	var target := Vector3.ZERO
	if inp.move_direction != Vector3.ZERO and player.camera:
		target = (player.camera.global_transform.basis * inp.move_direction).normalized() * speed

	# Разгон и торможение — разные: набирать ход призрак должен охотнее, чем
	# останавливаться, иначе инерция читается как «залипшее управление».
	var rate := gc.ghost_acceleration if target != Vector3.ZERO else gc.ghost_damping
	vel.velocity = vel.velocity.move_toward(target, rate * delta)

	# Прыжка у бестелесного нет: подниматься и опускаться он и так умеет, просто
	# посмотрев вверх или вниз. Флаг всё равно гасим — иначе нажатие, сделанное
	# призраком, сработает в тот самый миг, когда он вселится в тело.
	inp.jump_pressed = false
