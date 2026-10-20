# meta-description: Система GECS — поведение над сущностями из запроса (с правилами проекта).
# Группа: "input" | "gameplay" | "physics" — узел в World/Systems/<группа> и файл в src/systems/<группа>/ (system_order_check сверяет).
# Лучи и запросы к space-state — только из "physics" (Jolt на своём потоке).
#
# ЗАЧЕМ эта система: <причина в одну-две фразы, а не пересказ кода>.
class_name _CLASS_
extends System


func query() -> QueryBuilder:
	return q.with_all([])


## Порядок относительно других систем — только здесь, не порядком нод: GECS сортирует группу по Кану. Не нужен — удалить.
func deps() -> Dictionary[int, Array]:
	return {Runs.After: [], Runs.Before: []}


## Структурные правки (компонент/сущность) — только через cmd: система обходит архетипы zero-copy («Правило v9»). Поля писать можно.
func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	for entity in entities:
		pass
