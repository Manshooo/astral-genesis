## Сервировка места за столом (data/place_setting.tres): что останется от прибора на подносе (PlaceSetting) и насколько
## он сдвинут. Сцена прибора — полный набор для вида в редакторе; здесь веса, шансы и сцены-варианты, которые встают
## вместо нарисованного. Пустая сцена варианта — слот не заполняется. Вики: [[Расстановка пропов в комнатах]].
class_name RS_PlaceSetting
extends Resource

@export_group("Состояние места")
## Веса состояний: бросается одно на место.
@export var weight_empty := 4.0
## Поднос с тарелкой, напитком и приборами.
@export var weight_full := 3.0
## Поднос с одним напитком — тарелку унесли.
@export var weight_tray_drink := 1.0
## Напиток без подноса.
@export var weight_lone_drink := 1.5
## Тарелка без подноса.
@export var weight_lone_plate := 0.8

@export_group("Тарелка")
## Плошка — вариант тарелки, встаёт на её место.
@export var deep_bowl: PackedScene
@export_range(0.0, 1.0) var deep_bowl_chance := 0.35

@export_group("Напиток")
## Напиток на месте один: кружка из сцены прибора либо стакан отсюда.
@export var glass: PackedScene
@export_range(0.0, 1.0) var cup_chance := 0.6

@export_group("Приборы и мелочь")
@export_range(0.0, 1.0) var fork_chance := 0.85
@export_range(0.0, 1.0) var spoon_chance := 0.7
## Чайная ложка лежит только при кружке, со стаканом её нет.
@export_range(0.0, 1.0) var tea_spoon_chance := 0.8
@export var knife: PackedScene
@export_range(0.0, 1.0) var knife_chance := 0.6
@export var salad_bowl: PackedScene
@export_range(0.0, 1.0) var salad_bowl_chance := 0.4

@export_group("Сдвиги")
## Весь прибор: смещение по столу (м) и поворот (градусы) в обе стороны. Угол подноса у края стола —
## room_dressing_check сверяет, что он не свисает.
@export var setting_offset := 0.04
@export var setting_turn := 12.0
## Каждый предмет относительно подноса.
@export var item_offset := 0.012
@export var item_turn := 15.0
