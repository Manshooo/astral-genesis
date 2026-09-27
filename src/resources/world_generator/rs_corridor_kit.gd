## res://src/resources/world_generator/rs_corridor_kit.gd
## Набор кусков коридора: какая сцена ставится на тайл с данной маской проёмов
## (RS_LayerPlan.corridor_tiles) и как её повернуть.
##
## Данными, а не путями в коде: кит рисует арт, и новый вариант куска — правка
## data/corridor_kit.tres, а не генератора. Базовая маска у каждого куска —
## ориентация, в которой его НАРИСОВАЛИ (у кита P, как и у прежнего A: прямой
## открыт на север и юг, поворот — на запад и юг, Т — на север, восток и юг;
## сверяет лучами dev/corridor_spawn_check). Сборка крутит кусок на четверти оборота, пока повёрнутая маска не
## совпадёт с маской тайла; перерисованный в другой ориентации кусок чинится
## строкой здесь, а не в коде поворота.
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
## Торец с проёмом — на сторону тайла, упёршуюся в дверь комнаты. Стены кита —
## плоскости лицом внутрь, и без торца из коридора сквозь обратную сторону стены
## комнаты было бы видно всю комнату ([[Метрики и кит]] §2 п. 7). Нарисован на
## северной грани, как стены сборной комнаты (RS_RoomWallKit). Пусто — у кита
## торцов нет, и стык закрыть нечем.
@export var door_end: PackedScene


## Кусок под маску тайла: { "scene": PackedScene, "turns": четверти оборота
## вокруг Y }. Пусто — такого куска в ките нет (тупик, маска с одним проёмом,
## раскладка не выдаёт вовсе — см. dev/corridor_layout_check).
func piece_for(mask: int) -> Dictionary:
	for piece: Array in [[straight, straight_mask], [corner, corner_mask], [tee, tee_mask], [cross, cross_mask]]:
		if piece[0] == null:
			continue
		for turns in 4:
			if rotate_mask(piece[1], turns) == mask:
				return {"scene": piece[0], "turns": turns}
	return {}


## Кусок под маску тайла — уже повёрнутый, ещё не в дереве (позицию ставит
## зовущий, и ставит её ДО add_child: иначе коллизия успеет зарегистрироваться в
## начале координат). Один на игру и на предпросмотр «Генератора мира»: поставь
## они тайл каждый по-своему — и превью показывало бы не тот коридор, что
## построит игра. null — куска под маску в ките нет.
##
## [param doors] — какие из проёмов ведут в дверь комнаты (RS_LayerPlan.door_mask):
## на каждый встаёт торец door_end. Торец — ребёнок тайла, чтобы уходить и
## подсвечиваться вместе с ним; поворот у него поэтому свой минус поворот тайла.
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


## Маска после поворота на [param turns] четвертей оборота вокруг Y — в ту же
## сторону, что rotation.y = turns * PI / 2: восток уходит на север, север на
## запад, запад на юг, юг на восток. Знак здесь легко перепутать, и перепутанный
## он не падает, а ставит проёмы в стену — ловит dev/corridor_spawn_check.
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
