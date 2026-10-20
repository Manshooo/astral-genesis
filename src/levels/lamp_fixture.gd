## Плафон лампы уровня — заглушка до арта: корпус, светящаяся панель, тросик до потолка. Ребёнок LevelLight: она зовёт
## refresh() при смене энергии; погасшую лампу коридора стример заменяет тёмным плафоном (go_dark). Тросик меряется лучом
## в первом физкадре (space-state Jolt — только из _physics_process). Тени не отбрасывает: лампа внутри корпуса.
class_name LampFixture
extends Node3D

## Длиннее тросик не тянется: над коридором технический объём, луч ушёл бы в чужой пол.
const MAX_CABLE := 3.0
## Слой static_colliders — потолок.
const CEILING_MASK := 1
## Свечение панели на единицу энергии лампы: панель ярче освещённой стены.
const EMISSION_PER_ENERGY := 3.0
## Потолок свечения: у ламп с энергией в десятки (виварий — 20) панель выжигала бы кадр.
const MAX_EMISSION := 6.0

## Материал панели на пару «цвет, сила»: ~170 ламп слоя светят одинаково.
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


## Панель светится цветом и энергией лампы; тёмный плафон держит черноту.
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
