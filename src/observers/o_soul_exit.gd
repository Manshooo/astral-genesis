# res://src/observers/o_soul_exit.gd
# Наблюдатель: выход из тела оставляет в мире брошенное тело (SoulExitFx) — оно валится рэгдоллом и испаряется к душе.
# Сидит на событии expelled_from_body, а не на снятии C_Embodied: к снятию путь сцены тела и место подошвы уже потеряны.
class_name O_SoulExit
extends Observer

const FX_SCENE := preload("res://src/entities/player/soul_exit_fx.tscn")


func query() -> QueryBuilder:
	return q.with_all([C_SoulCloud]).on_event(&"expelled_from_body")


func each(_event: Variant, entity: Entity, payload: Variant = null) -> void:
	if not payload is Dictionary:
		return
	var exit: Dictionary = payload
	if String(exit.get("body_scene_path", "")).is_empty():
		return
	var body_scene := load(exit.body_scene_path) as PackedScene
	var soul := entity as Node as Node3D
	if body_scene == null or soul == null or soul.get_parent() == null:
		return
	var fx := FX_SCENE.instantiate() as SoulExitFx
	# Рядом с душой, а не под комнатой: эффект живёт пару секунд и снос комнаты ему не нужен.
	soul.get_parent().add_child(fx)
	fx.start(body_scene, exit.placement, exit.velocity, soul)
