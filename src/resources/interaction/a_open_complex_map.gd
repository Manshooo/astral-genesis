## res://src/resources/interaction/a_open_complex_map.gd
## Открывает экран карты комплекса — тот же, что по клавише карты. Терминал в
## хабе нужен не ради другого экрана, а ради места: карта, развёрнутая на стене
## лаборатории, — это то, где забег планируют перед выходом. Решение «открыть
## или сказать, что связи нет» принимает UIManager, поэтому терминал и клавиша
## не разъедутся.
class_name A_OpenComplexMap
extends RS_InteractionAction


func execute(_entity: Entity, _interactor: Node = null) -> void:
	UIManager.open_complex_map()
