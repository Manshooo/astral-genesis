# res://src/systems/physics/s_interaction_detector.gd
# Группа "physics": луч от глаз к точке под прицелом (AimRay) — запрос к space-state. Держит C_Highlighted на интерактиве
# под прицелом в пределах interact_range от тела; стена луч обрывает. Нажатие читает S_InteractInput, подсветку и подсказку
# рисуют O_OutlineVisual и HUD по той же метке. Вики: [[Взаимодействие]].
class_name S_InteractionDetector
extends System

## Что видит луч: стены (static_colliders, бит 0) — чтобы не доставать сквозь них — и интерактивы (бит 3). Двери на
## moving_colliders в маске нет: их полотно стоит в том же проёме, что и объём, по которому их открывают.
const RAY_MASK := (1 << 0) | (1 << 3)
const INTERACTIVES_BIT := 1 << 3

var _current_target: Entity = null


func query() -> QueryBuilder:
	return q.with_all([C_PlayerInput, C_ThirdPersonCamera]).with_none([C_UIBlocked])


## После S_CameraAim: луч идёт к точке под прицелом этого тика, из точки тела после перемещения.
func deps() -> Dictionary[int, Array]:
	return {Runs.After: [S_Movement, S_CameraAim]}


func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	if entities.is_empty():
		_clear_target()
		return

	var player := entities[0] as E_Player
	if player == null or player.view_camera == null:
		_clear_target()
		return

	var params := AimRay.query(player, SettingsManager.settings.interact_range, RAY_MASK)
	# Глаза бывают внутри объёма интерактива (терминал вплотную) — такой объём тоже цель.
	params.hit_from_inside = true
	var hit := player.view_camera.get_world_3d().direct_space_state.intersect_ray(params)

	var target: Entity = null
	if not hit.is_empty():
		var collider := hit.collider as CollisionObject3D
		if collider != null and collider.collision_layer & INTERACTIVES_BIT != 0:
			target = _resolve_interactable(collider)

	if target != _current_target:
		if _current_target and is_instance_valid(_current_target):
			cmd.remove_component(_current_target, C_Highlighted)
		if target:
			cmd.add_component(target, C_Highlighted.new())
		_current_target = target


## Вверх от коллайдера до Entity с C_Interactable (луч попадает в дочерний CollisionShape3D).
func _resolve_interactable(collider: Object) -> Entity:
	var node := collider as Node
	while node:
		if node is Entity and node.has_component(C_Interactable):
			var c := node.get_component(C_Interactable) as C_Interactable
			return node if c.enabled else null
		node = node.get_parent()
	return null


func _clear_target() -> void:
	if _current_target and is_instance_valid(_current_target):
		cmd.remove_component(_current_target, C_Highlighted)
	_current_target = null
