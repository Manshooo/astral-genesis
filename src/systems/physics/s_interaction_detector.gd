# res://src/systems/physics/s_interaction_detector.gd
# Группа "physics": луч интеракции обновляется force_raycast_update() — запрос к space-state. Держит C_Highlighted на интерактиве под взглядом; нажатие читает S_InteractInput,
# подсветку и подсказку рисуют O_OutlineVisual и HUD по той же метке. Вики: [[Взаимодействие]].
class_name S_InteractionDetector
extends System

var _current_target: Entity = null


func query() -> QueryBuilder:
	return q.with_all([C_PlayerInput]).with_none([C_UIBlocked])


## После S_Movement: луч идёт от камеры, из точки тела после перемещения.
func deps() -> Dictionary[int, Array]:
	return {Runs.After: [S_Movement]}


func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	if entities.is_empty():
		_clear_target()
		return

	var e_player := entities[0] as E_Player
	if e_player == null or e_player.interact_ray == null:
		_clear_target()
		return

	var ray := e_player.interact_ray
	var s := SettingsManager.settings
	ray.target_position = Vector3(0, 0, -s.interact_range)
	ray.force_raycast_update()

	var target: Entity = null
	if ray.is_colliding():
		target = _resolve_interactable(ray.get_collider())

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
