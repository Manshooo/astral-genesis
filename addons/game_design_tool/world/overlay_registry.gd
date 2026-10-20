## res://addons/game_design_tool/world/overlay_registry.gd
## Список оверлеев вьюпорта генератора: вкладка «Генератор мира» и GDT_ViewportHost
## ходят по нему циклом, новый оверлей — одна строка здесь плюс файл в overlays/.
## [[Редакторские инструменты]] §«Коридоры и сетка во вьюпорте».
@tool
extends RefCounted

## id — ключ сохранённой галочки (его переименование её сбрасывает); script —
## оверлей с rebuild(GDT_LayerView) и set_selected(StringName).
const OVERLAYS := [
	{
		"id": &"rooms",
		"title": "Геометрия",
		"tooltip": "Показать геометрию комнат и коридоров — те же сцены и куски кита, что в игре",
		"default_visible": true,
		"script": preload("res://addons/game_design_tool/world/overlays/rooms_overlay.gd"),
	},
	{
		"id": &"graph",
		"title": "Граф",
		"tooltip": "Показать граф комнат",
		"default_visible": true,
		"script": preload("res://addons/game_design_tool/world/overlays/graph_overlay.gd"),
	},
	{
		"id": &"labels",
		"title": "Подписи",
		"tooltip": "Показать id, пресет и теги узла над каждой комнатой",
		"default_visible": true,
		"script": preload("res://addons/game_design_tool/world/overlays/labels_overlay.gd"),
	},
	{
		"id": &"corridors",
		"title": "Коридоры",
		"tooltip": "Показать план коридоров: трасса веток по клеткам и проёмы тайлов",
		"default_visible": true,
		"script": preload("res://addons/game_design_tool/world/overlays/corridors_overlay.gd"),
	},
	{
		"id": &"grid",
		"title": "Сетка",
		"tooltip": "Показать клетки плана: решётку слоя, footprint и поворот комнат (стрелка — куда смотрит север сцены), сокеты (дверь — стрелкой внутрь цветом ветки, глухой — тусклой чертой), тупики и стыки веток",
		"default_visible": true,
		"script": preload("res://addons/game_design_tool/world/overlays/grid_overlay.gd"),
	},
]
