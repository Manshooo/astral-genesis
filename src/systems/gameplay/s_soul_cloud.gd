# res://src/systems/gameplay/s_soul_cloud.gd
# Группа "gameplay". Ведёт облик души (C_SoulCloud): вне тела голова-сгусток тянется по следу, во плоти облик гаснет
# весь — со следом и клочьями у камеры. Сверка с C_Embodied каждый кадр, а не наблюдателем: так же после загрузки в теле.
class_name S_SoulCloud
extends System


func query() -> QueryBuilder:
	return q.with_all([C_SoulCloud])


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	for entity in entities:
		var cloud := entity.get_component(C_SoulCloud) as C_SoulCloud
		var shown := not entity.has_component(C_Embodied)
		if int(shown) != cloud.applied:
			_show(entity, cloud, shown)
		if shown:
			_animate(entity, cloud, delta)


func _show(entity: Entity, cloud: C_SoulCloud, shown: bool) -> void:
	# Вышла из тела — сгусток разворачивается из сжатого; появилась с самого начала (applied = −1) — сразу целиком.
	cloud.unfold = 0.0 if shown and cloud.applied == 0 else 1.0
	cloud.applied = int(shown)
	for path in [cloud.root_path, cloud.wisps_path]:
		var node := entity.get_node_or_null(path) as Node3D
		if node == null:
			continue
		node.visible = shown
		var particles: Array = node.find_children("*", "GPUParticles3D", true, false)
		if node is GPUParticles3D:
			particles.append(node)
		for p: GPUParticles3D in particles:
			p.emitting = shown
	if shown:
		# Душа вышла не там, где пряталась: старый след стянул бы голову из прошлого места.
		cloud.history.resize(cloud.samples)
		cloud.history.fill((entity as Node as Node3D).global_position)


func _animate(entity: Entity, cloud: C_SoulCloud, delta: float) -> void:
	var head := entity.get_node_or_null(cloud.head_path) as MultiMeshInstance3D
	if head == null or head.multimesh == null:
		return
	if cloud.offsets.size() != cloud.count:
		_seed_cards(cloud, head)
	cloud.time += delta
	cloud.unfold = minf(cloud.unfold + delta / maxf(cloud.unfold_seconds, 0.001), 1.0)
	var grow := smoothstep(0.0, 1.0, cloud.unfold)
	# Дыхание: сгусток медленно расширяется и сжимается — живое, а не висящее облако.
	var breath := 1.0 + cloud.breath_amount * sin(cloud.time * TAU / maxf(cloud.breath_period, 0.1))
	var spread := lerpf(0.25, 1.0, grow) * breath
	var center := (entity as Node as Node3D).global_position
	_record(cloud, center, delta)
	# Голова стоит в центре души, карточки — относительно неё: AABB вокруг узла, а не вокруг начала мира,
	# где уровень может и не лежать.
	head.global_transform = Transform3D(Basis.IDENTITY, center)
	head.set_instance_shader_parameter(&"blob_center", center)
	_apply_decay(entity, cloud, head, grow)

	var eye := Vector3.ZERO
	var camera := entity.get_viewport().get_camera_3d()
	if camera != null:
		eye = camera.global_position
	var xforms: Array[Transform3D] = []
	var customs: Array[Color] = []
	var order: Array[int] = []
	for i in cloud.count:
		var s := cloud.seeds[i]
		var wobble := Vector3(sin(cloud.time * 0.9 + s * 6.0), sin(cloud.time * 1.1 + s * 4.0), cos(cloud.time * 0.8 + s * 5.0)) * 0.04
		# Бегущая волна по пелене: клочки отходят от центра и возвращаются по очереди, как по живой ткани.
		var o := cloud.offsets[i]
		var wave := 1.0 + cloud.wave_amount * sin(cloud.time * 1.7 - o.x * 3.0 - o.z * 2.0)
		var pos := _sample(cloud, cloud.sizes[i] * cloud.drag) + (_lobe(cloud, i % maxi(cloud.lobes, 1)) \
				+ o * cloud.radius * (1.0 - cloud.lobe_spread * 0.4) * wave) * spread + wobble
		var size := lerpf(cloud.card_size.x, cloud.card_size.y, cloud.sizes[i]) * lerpf(0.4, 1.0, grow)
		var core := 1.0 - cloud.offsets[i].length() * 0.5
		var rot := s + cloud.time * cloud.spin * 0.15 * (s - 0.5)
		xforms.append(Transform3D(Basis.from_scale(Vector3.ONE * size), pos))
		customs.append(Color(core, s, 1.0, rot))
		order.append(i)
	# Прозрачные экземпляры MultiMesh движок не сортирует — дальние рисуем первыми сами.
	order.sort_custom(func(a: int, b: int) -> bool:
		return xforms[a].origin.distance_squared_to(eye) > xforms[b].origin.distance_squared_to(eye))
	for k in order.size():
		head.multimesh.set_instance_transform(k, xforms[order[k]].translated(-center))
		head.multimesh.set_instance_custom_data(k, customs[order[k]])


## Чем ближе распад, тем призрачнее: клочки бледнеют и рвутся (шейдер), частиц в следе и у камеры меньше.
## Запас — через UI_HudMood, как у свечения и дуги: своя формула разошлась бы с ними. Разворачиваясь после
## выхода, облик собирается из рваного тем же параметром: grow 0 — как на исходе, 1 — по запасу.
func _apply_decay(entity: Entity, cloud: C_SoulCloud, head: MultiMeshInstance3D, grow: float) -> void:
	var vitals := UI_HudMood.read_vitals(entity)
	cloud.decay = UI_HudMood.decay(vitals.active()) if vitals != null else 0.0
	var d := maxf(cloud.decay, 1.0 - grow)
	head.set_instance_shader_parameter(&"decay", d)
	for path in [cloud.trail_path, cloud.wisps_path]:
		var particles := entity.get_node_or_null(path) as GPUParticles3D
		if particles == null:
			continue
		particles.set_instance_shader_parameter(&"decay", d)
		particles.amount_ratio = lerpf(1.0, cloud.decay_amount, d)


func _seed_cards(cloud: C_SoulCloud, head: MultiMeshInstance3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = cloud.rng_seed
	cloud.offsets.clear()
	cloud.seeds.clear()
	cloud.sizes.clear()
	for i in cloud.count:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		cloud.offsets.append(dir.normalized() * pow(rng.randf(), 0.6) * cloud.shape)
		cloud.seeds.append(rng.randf())
		cloud.sizes.append(rng.randf())
	head.multimesh.instance_count = cloud.count


## След — по времени, не по пути: на остановке точки догоняют голову, и хвост стягивается сам.
func _record(cloud: C_SoulCloud, center: Vector3, delta: float) -> void:
	if cloud.history.size() != cloud.samples:
		cloud.history.resize(cloud.samples)
		cloud.history.fill(center)
	var step := cloud.trail_seconds / cloud.samples
	cloud.history_acc += delta
	while cloud.history_acc >= step:
		cloud.history_acc -= step
		for i in range(cloud.samples - 1, 0, -1):
			cloud.history[i] = cloud.history[i - 1]
	cloud.history[0] = center


## Точка следа: 0 — сейчас, 1 — самая старая.
func _sample(cloud: C_SoulCloud, t: float) -> Vector3:
	var f := clampf(t, 0.0, 1.0) * (cloud.samples - 1)
	var i := mini(int(f), cloud.samples - 2)
	return cloud.history[i].lerp(cloud.history[i + 1], f - i)


func _lobe(cloud: C_SoulCloud, k: int) -> Vector3:
	if cloud.lobes <= 1:
		return Vector3.ZERO
	var p := k * 2.1
	return Vector3(sin(cloud.time * 0.37 + p * 1.3), 0.5 * sin(cloud.time * 0.29 + p * 2.7), cos(cloud.time * 0.31 + p * 0.9)) \
			* cloud.radius * cloud.lobe_spread * cloud.shape
