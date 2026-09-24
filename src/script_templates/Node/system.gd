# meta-description: Система GECS — поведение над сущностями из запроса (с правилами проекта).
# Группа: "input" | "gameplay" | "physics" — узел под World/Systems/<группа> в
# world.tscn, файл — в src/systems/<группа>/ (system_order_check сверяет одно с
# другим). Лучи и прочие запросы к space-state — только из "physics": Jolt
# крутится на своём потоке.
#
# ЗАЧЕМ эта система: <причина в одну-две фразы, а не пересказ кода>.
class_name _CLASS_
extends System


func query() -> QueryBuilder:
	return q.with_all([])


## Порядок относительно других систем — только здесь, не порядком нод в сцене:
## GECS сортирует группу по Кану, и система с входящей зависимостью уезжает в
## конец очереди. Не нужен — удалить.
func deps() -> Dictionary[int, Array]:
	return {Runs.After: [], Runs.Before: []}


## Структурные правки (компонент или сущность добавить/снять) — только через cmd:
## система обходит архетипы zero-copy, и прямая правка пропустит соседей по
## проходу («Правило v9»). Поля компонентов писать напрямую можно.
func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	for entity in entities:
		pass
