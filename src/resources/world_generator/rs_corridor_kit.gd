## res://src/resources/world_generator/rs_corridor_kit.gd
## Набор кусков коридора: какая сцена ставится на тайл с данной маской проёмов (RS_LayerPlan.corridor_tiles) и как её повернуть.
## Данными (data/corridor_kit.tres): новый вариант куска — правка данных. Базовая маска — ориентация, в которой кусок НАРИСОВАЛИ (прямой —
## север и юг, поворот — запад и юг, Т — север, восток, юг, тупик — юг; сверяет лучами dev/corridor_spawn_check); сборка крутит на четверти оборота до совпадения.
@tool  # читается рантаймом и вкладкой «Генератор мира»
class_name RS_CorridorKit
extends Resource

@export var straight: PackedScene
@export var straight_mask: int = 5  # север + юг
@export var corner: PackedScene
@export var corner_mask: int = 12  # юг + запад
@export var tee: PackedScene
@export var tee_mask: int = 7  # север + восток + юг
@export var cross: PackedScene
@export var cross_mask: int = 15
## Тупик — тайл с одним проёмом (RS_LayerPlan.dead_ends). Пусто — тупика нет, такой тайл не встанет.
@export var end: PackedScene
@export var end_mask: int = 4  # юг
## Торец с проёмом — на сторону тайла, упёршуюся в дверь комнаты: стены кита — плоскости лицом внутрь, и без торца сквозь обратную сторону стены комнаты
## было бы видно всю комнату ([[Метрики и кит]] §2 п. 7). Нарисован на северной грани, как стены сборной комнаты. Пусто — стык закрыть нечем.
@export var door_end: PackedScene


## Кусок под маску: { "scene": PackedScene, "turns": четверти оборота вокруг Y }. Пусто — куска нет.
func piece_for(mask: int) -> Dictionary:
	var pieces: Array[Array] = [
		[straight, straight_mask], [corner, corner_mask], [tee, tee_mask], [cross, cross_mask], [end, end_mask]
	]
	for piece: Array in pieces:
		if piece[0] == null:
			continue
		for turns in 4:
			if rotate_mask(piece[1], turns) == mask:
				return {"scene": piece[0], "turns": turns}
	return {}


## Кусок под маску — уже повёрнутый, ещё не в дереве (позицию ставит зовущий ДО add_child, иначе коллизия зарегистрируется в начале координат).
## Один на игру и предпросмотр «Генератора мира». [param doors] — проёмы в дверь комнаты (RS_LayerPlan.door_mask): на каждый встаёт торец door_end,
## ребёнок тайла — поворот у него свой минус поворот тайла. null — куска под маску нет.
func instantiate(mask: int, doors: int = 0) -> Node3D:
	var piece := piece_for(mask)
	if piece.is_empty():
		return null
	var tile := (piece["scene"] as PackedScene).instantiate() as Node3D
	var turns: int = piece["turns"]
	tile.rotation.y = turns * PI * 0.5
	if door_end:
		for side in SquareGridTopology.SIDE_COUNT:
			if doors & (1 << side):
				var cap := door_end.instantiate() as Node3D
				cap.rotation.y = (RS_RoomLayout.north_piece_turns(side) - turns) * PI * 0.5
				tile.add_child(cap)
	return tile


## Маска после поворота на turns четвертей вокруг Y — как rotation.y = turns·π/2: восток→север→запад→юг→восток. Знак легко перепутать,
## и перепутанный он ставит проёмы в стену — ловит dev/corridor_spawn_check.
static func rotate_mask(mask: int, turns: int) -> int:
	for i in posmod(turns, 4):
		var turned := 0
		if mask & 1:
			turned |= 8  # север → запад
		if mask & 2:
			turned |= 1  # восток → север
		if mask & 4:
			turned |= 2  # юг → восток
		if mask & 8:
			turned |= 4  # запад → юг
		mask = turned
	return mask
