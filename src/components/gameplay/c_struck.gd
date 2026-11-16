# res://src/components/gameplay/c_struck.gd
# Последний удар по сущности — откуда и когда: S_Attack пишет, O_EnemyDeath отдаёт трупу, чтобы удар, уронивший
# тело, разбросал его конечности (C_Ragdoll.struck_from). Вики: [[Захват тела]].
class_name C_Struck
extends Component

## Удар старше этого уже не тот, что уронил: тело умерло от чего-то другого.
const FRESH_MSEC := 1000

## От ударившего к цели, по горизонтали, единичный.
var direction := Vector3.ZERO
## Time.get_ticks_msec() удара.
var at_msec := -FRESH_MSEC


func is_fresh() -> bool:
	return Time.get_ticks_msec() - at_msec <= FRESH_MSEC
