# res://src/systems/gameplay/s_soul_glow.gd
# Группа: "gameplay". Ведёт свечение души (C_SoulGlow): энергия гаснет по той же
# кривой распада, что давит экран HUD, цвет перетекает между сиреневым и янтарём
# вместе с дугой.
#
# Запасы читаются через UI_HudMood.read_vitals, а не своими формулами: «какой
# карман убывает» и «какая у него доля» уже решены там тем же правилом, что у
# S_Lifespan, и второй расчёт рядом разошёлся бы с дугой при первой правке. По
# той же причине энергия — от UI_HudMood.decay(): свет тускнеет ровно тогда,
# когда экран начинает давить, а не линейно — ранний запас около минуты, и
# линейно душа светила бы вполсилы почти всегда.
class_name S_SoulGlow
extends System


func query() -> QueryBuilder:
	return q.with_all([C_SoulGlow])


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	for entity in entities:
		var glow := entity.get_component(C_SoulGlow) as C_SoulGlow
		var light := entity.get_node_or_null(glow.light_path) as Light3D
		var vitals := UI_HudMood.read_vitals(entity)
		if light == null or vitals == null:
			continue
		glow.body_mix = move_toward(glow.body_mix, 1.0 if vitals.body_pocket else 0.0,
			delta / UI_DecayArc.TINT_SECONDS)
		light.light_color = UI_HudMood.SOUL.lerp(UI_HudMood.BODY, glow.body_mix)
		light.light_energy = lerpf(glow.energy_full, glow.energy_faded, UI_HudMood.decay(vitals.active()))
