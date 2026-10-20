## res://src/resources/interaction/a_open_complex_map.gd
## Открывает экран карты комплекса — тот же, что по клавише; терминал в хабе — ради места планирования. Решение «открыть или связи нет» — за UIManager.
class_name A_OpenComplexMap
extends RS_InteractionAction


func execute(_entity: Entity, _interactor: Node = null) -> void:
	UIManager.open_complex_map()
