## res://src/resources/level_gen/rs_level_connection.gd
## Хранится ассиметрично - на каждом конце связи лежит своя RS_LevelConnection
## (см. RunManager._link_nodes), поэтому one_way реализуется просто отсутствием
## обратного ребра, а не флагом направления внутри одного объекта.
class_name RS_LevelConnection
extends Resource

enum Type { DOOR, CORRIDOR, ELEVATOR, STAIRWELL, COLLAPSE, SHORTCUT }

## Куда ведёт это ребро.
@export var target_node_id: StringName = &""
## Тип связи — влияет на то, какой преф спавнится в месте прохода
## (обычная дверь/коридор или интерактивный коннектор — лифт/лестница).
@export var type: Type = Type.DOOR
## Истинно one-way связи (обвалы) создаются вообще без обратного ребра —
## этот флаг просто помогает отличить такие рёбра при отладке/визуализации.
@export var one_way: bool = false
## Если не пусто — связь заперта, пока у игрока нет соответствующего
## ключа/навыка. Пустая строка = связь открыта всегда.
@export var locked_by: StringName = &""
## -1 при переходе на уровень ниже, +1 выше, 0 для горизонтальных связей.
@export var depth_delta: int = 0


func is_locked() -> bool:
	return locked_by != &""
