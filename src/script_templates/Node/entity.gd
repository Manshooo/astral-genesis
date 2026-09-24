# meta-description: Сущность GECS — контейнер компонентов; поведение живёт в системах.
# ЗАЧЕМ эта сущность: <причина в одну-две фразы>.
#
# Числа, которые тюнит дизайнер, — компонентами в сцене (component_resources).
# Компоненты-идентичность, которые обязаны пережить смену тела или сцены, — в
# define_components() (см. E_Player).
@tool
class_name _CLASS_
extends Entity


func define_components() -> Array:
	return []
