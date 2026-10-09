## Плафон лампы уровня — заглушка до арта: корпус, светящаяся панель и тросик до
## потолка.
##
## Ребёнок LevelLight: лампа зовёт refresh(), когда меняет энергию (слой), и
## панель светится цветом и силой самой лампы — глубже тусклее вместе с ней.
## Погасшую лампу коридора стример снимает, а плафон пересаживает на тайл тёмным
## (go_dark): пропавший светильник читался бы недостроенным потолком, а мёртвый —
## местом, где что-то сломалось.
##
## Тросик меряется лучом вверх в первом физкадре.
## Луч — из _physics_process: space-state Jolt безопасен только оттуда.
##
## Тени не отбрасывает ни одна часть: лампа сидит внутри корпуса, и его тень
## легла бы на весь потолок.
class_name LampFixture
extends Node3D

## Длиннее тросик не тянется: над коридором (5 м) — технический объём до клетки
## этажом выше, и луч, не нашедший потолка ближе, ушёл бы в чужой пол.
const MAX_CABLE := 3.0
## Слой static_colliders — потолок; тела, двери и интерактивы тросик не держат.
const CEILING_MASK := 1
## Свечение панели на единицу энергии лампы: панель — видимый источник, и при
## равной энергии она обязана читаться ярче освещённой ею стены.
const EMISSION_PER_ENERGY := 3.0
## Ярче панель не светится: у ламп с энергией в десятки (виварий — 20) она
## выжигала бы кадр свечением, а сильнее, чем «белое», источник не читается.
const MAX_EMISSION := 6.0

## Материал панели на пару «цвет, сила»: лампы слоя светят одинаково, и свой
## материал на каждую из ~170 дробил бы отрисовку без всякой разницы в картинке.
static var _panel_materials: Dictionary = {}

var _dark := false

@onready var _panel := $Panel as MeshInstance3D
@onready var _cable := $Cable as MeshInstance3D


func _ready() -> void:
	_cable.visible = false
	var light := get_parent() as Light3D
	if _dark or light == null:
		refresh(Color.BLACK, 0.0)
	else:
		refresh(light.light_color, light.light_energy)


func _physics_process(_delta: float) -> void:
	set_physics_process(false)
	var top := _cable.global_position
	var query := PhysicsRayQueryParameters3D.create(top, top + Vector3.UP * MAX_CABLE, CEILING_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var length := top.distance_to(hit.position)
	_cable.scale.y = length
	_cable.position.y += length * 0.5
	_cable.visible = true


## Панель светится цветом и энергией лампы. Тёмный плафон держит черноту, что бы
## ему ни прислали.
func refresh(color: Color, energy: float) -> void:
	if _panel:
		_panel.material_override = _material(color, 0.0 if _dark else energy)


## Лампа погасла: плафон остаётся висеть, но не светится.
func go_dark() -> void:
	_dark = true
	refresh(Color.BLACK, 0.0)


static func _material(color: Color, energy: float) -> StandardMaterial3D:
	var key := "%s|%.2f" % [color.to_html(false), energy]
	if _panel_materials.has(key):
		return _panel_materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.08, 0.08, 0.09)
	material.roughness = 0.6
	if energy > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = minf(energy * EMISSION_PER_ENERGY, MAX_EMISSION)
	_panel_materials[key] = material
	return material
