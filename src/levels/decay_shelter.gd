## Убежище от распада: пока душа внутри объёма, её запас не убывает, а
## восполняется (S_DecayShelter). Первое стоит в хабе — у входа в комплекс игрок
## может перевести дух, прежде чем уйти вглубь.
##
## Area3D, а не клетка плана, как у S_RoomPresence и S_VoidFall: убежище — это
## не «вся комната», а место, которое автор очерчивает в сцене руками, и рамку
## удобнее всего видеть и тянуть в редакторе. Коллизий она не создаёт и сама
## никого не держит: ловит только слой игрока (collision_mask = player) — тела и
## враги в убежище не прячутся, у них нет запаса души.
##
## Узел только ставит и снимает маркер C_Sheltered — логики распада здесь нет.
## Выгружается слой вместе с зоной — Area3D сама шлёт body_exited при выходе из
## дерева, и маркер снимается тем же путём, что при обычном выходе.
class_name DecayShelter
extends Area3D

## Сколько секунд запаса возвращается за секунду. 10 — пустой минутный запас
## наполняется за шесть секунд: укрытие ощутимо, но в нём не стоят столбом.
@export var refill_rate: float = 10.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


## Структурная правка — отложенно: сигналы физики приходят между кадрами, но
## гарантировать, что ни одна система в этот момент не идёт по архетипам, нам
## нечем (правило v9, docs/.../GECS и правила движка.md). Отложенные вызовы
## исполняются по порядку, так что вход и выход в одном кадре не перепутаются.
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
		# Перекрытие зон: темп — больший из двух, иначе шаг через общую границу
		# менял бы скорость восполнения в зависимости от порядка входа.
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
