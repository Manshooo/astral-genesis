## res://src/resources/world_generator/rs_room_type.gd
## Тип помещения комплекса (арсенал, лаборатория, склад) — «ЧТО это за помещение»; структурных обязательств нет. Не tags (те — жёсткий
## фильтр вместимости): тег типа стал бы требованием (см. RS_RoomPresetLibrary).
@tool  # каталог правится и читается из вкладки «Редактор пресетов»
class_name RS_RoomType
extends Resource

## Ключ типа (`arsenal`, `lab`, `storage`) — в RS_RoomPreset.room_type и RS_LevelNode.room_type, сравнение по нему.
@export var id: StringName = &""

## Имя для инструментов и логов — готовой строкой, игроку не показывается (у карты свой map_name).
@export var display_name: String = ""

## Заметка дизайнера, в игру не попадает; пустое — не ошибка.
@export_multiline var description: String = ""

## Вес в розыгрыше типа для узла; <= 0 выключает тип.
@export var weight: float = 1.0

## Название на карте (четвёртый уровень) — ключ перевода, отдельно от display_name (строки для инструментов не переводятся). Пусто — display_name (validate называет).
@export var map_name: String = ""

## Значок на карте; пусто — заглушка из первой буквы map_label().
@export var map_icon: Texture2D

@export_group("Глубина")

## Границы по номеру слоя (0 — поверхность, 5 — дно; RS_LevelGraph.DEPTHS): тип разыгрывается только на узлах с depth в отрезке включительно —
## казармы ближе к поверхности, содержание существ глубже.
@export var depth_min: int = 0
@export var depth_max: int = 5


## Годится ли тип для узла такой глубины.
func covers_depth(depth: int) -> bool:
	return depth >= depth_min and depth <= depth_max


## Для инструментов и логов: имя, если задано, иначе ключ.
func label() -> String:
	return display_name if display_name != "" else String(id)


## Имя для карты: map_name, иначе label(); ключ перевода и готовая строка проходят через tr().
func map_label() -> String:
	return map_name if map_name != "" else label()
