## Убежище от распада: пока душа внутри объёма, запас восполняется (S_DecayShelter). Area3D, а не клетка плана: рамку
## автор тянет в редакторе. Ловит только слой игрока; узел лишь ставит и снимает C_Sheltered. Вики: [[Захват тела]] (распад).
class_name DecayShelter
extends Area3D

## Секунд запаса в секунду: 10 — пустой минутный запас наполняется за шесть секунд.
@export var refill_rate: float = 10.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


## Структурная правка — отложенно (правило v9): сигналы физики приходят между кадрами; вызовы идут по порядку.
func _on_body_entered(body: Node3D) -> void:
	var soul := body as Node as Entity
	if soul != null and soul.has_component(C_Lifespan):
		_shelter.call_deferred(soul, refill_rate)


func _on_body_exited(body: Node3D) -> void:
	var soul := body as Node as Entity
	if soul != null:
		_unshelter.call_deferred(soul)


static func _shelter(soul: Entity, rate: float) -> void:
	if not is_instance_valid(soul):
		return
	var sheltered := soul.get_component(C_Sheltered) as C_Sheltered
	if sheltered:
		# Перекрытие зон: темп — больший из двух, иначе он зависел бы от порядка входа.
		sheltered.zones += 1
		sheltered.refill_rate = maxf(sheltered.refill_rate, rate)
		return
	sheltered = C_Sheltered.new()
	sheltered.refill_rate = rate
	soul.add_component(sheltered)


static func _unshelter(soul: Entity) -> void:
	if not is_instance_valid(soul):
		return
	var sheltered := soul.get_component(C_Sheltered) as C_Sheltered
	if sheltered == null:
		return
	sheltered.zones -= 1
	if sheltered.zones <= 0:
		soul.remove_component(C_Sheltered)
