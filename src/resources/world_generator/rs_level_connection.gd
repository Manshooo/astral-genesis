## res://src/resources/world_generator/rs_level_connection.gd
## Хранится асимметрично: на каждом конце своя RS_LevelConnection (RS_LevelGraph._link_nodes), one_way — отсутствием обратного ребра.
@tool  # граф строится в т.ч. из редакторской вкладки «Генератор мира» — см. RS_LevelGraph
class_name RS_LevelConnection
extends Resource

enum Type { DOOR, CORRIDOR, ELEVATOR, STAIRWELL, COLLAPSE, SHORTCUT }

## Куда ведёт ребро.
@export var target_node_id: StringName = &""
## Тип связи — какой преф спавнится в месте прохода.
@export var type: Type = Type.DOOR
## Помогает отличить one-way рёбра при отладке (обратного ребра нет вовсе).
@export var one_way: bool = false
## Не пусто — заперто, пока нет ключа/навыка.
@export var locked_by: StringName = &""
## -1 вниз, +1 вверх, 0 горизонтально.
@export var depth_delta: int = 0


func is_locked() -> bool:
	return locked_by != &""


## Ребро портала (ELEVATOR и STAIRWELL, RS_LevelGraph._link_vertical). По типу, не по разнице этажей: верхняя дверь лестницы — обычное коридорное ребро.
func is_portal() -> bool:
	return type == Type.ELEVATOR or type == Type.STAIRWELL
