# res://src/systems/gameplay/s_decay_sound.gd
# Группа "gameplay". Ведёт петлю распада (C_DecaySound): проступает, когда убывающий карман падает ниже порога дуги, и гаснет над ним; напряжение — параметром события.
# Запас и сила распада — через UI_HudMood.read_vitals и decay(), не своими формулами: звук разошёлся бы с дугой и экраном. Вики: [[Звук]] §3б.
class_name S_DecaySound
extends System


func query() -> QueryBuilder:
	return q.with_all([C_DecaySound])


## После S_Lifespan: слышно тот карман, что уже убыл в этом кадре.
func deps() -> Dictionary[int, Array]:
	return {Runs.After: [S_Lifespan]}


func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	for entity in entities:
		var sound := entity.get_component(C_DecaySound) as C_DecaySound
		var vitals := UI_HudMood.read_vitals(entity)
		var d := UI_HudMood.decay(vitals.active()) if vitals else 0.0

		if d <= 0.0:
			if sound.instance != null:
				# Затухание доигрывает рантайм: просто уронить ссылку — деструктор биндинга оборвал бы голос сразу.
				sound.instance.release_after_fade_out(sound.fade_out)
				sound.instance = null
			continue

		if sound.instance == null:
			# null — штатно (нет рантайма или события): спросим снова на следующем кадре распада.
			sound.instance = AudioManager.create_event_instance(sound.event_path)
			if sound.instance == null:
				continue
			sound.instance.start()
			sound.instance.fade_in(sound.fade_in)

		if not sound.intensity_parameter.is_empty():
			sound.instance.set_parameter(sound.intensity_parameter, lerpf(sound.intensity_calm, sound.intensity_max, d))
