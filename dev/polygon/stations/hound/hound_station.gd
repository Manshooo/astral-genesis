extends Node3D
## Станция «Анимации hound»: стенд клипов (клип сам по себе), беговая дорожка (машина состояний на манекене) и мат с
## телом (от первого лица). У каждой части свой пульт; пульты стенда и дорожки открывают экран с камерой облёта.
## Станция полигона: title, маркер Spawn, setup(polygon) — dev/polygon/polygon.gd. Вики: [[Полигон]].

const CLIP_SCREEN := preload("res://dev/polygon/stations/hound/clip_screen.tscn")
const STATE_SCREEN := preload("res://dev/polygon/stations/hound/state_screen.tscn")

@export var title := "Анимации hound"

var polygon: Node

@onready var stand: Node3D = %ClipStand
@onready var treadmill: Node3D = %Treadmill
@onready var mat: Node3D = %BodyMat


func setup(owner_polygon: Node) -> void:
	polygon = owner_polygon
	stand.setup(polygon.clips)
	treadmill.spawn_puppet()
	mat.lay_body()
	(%StandConsole as E_InteractableObject).interacted.connect(func(_e: Entity) -> void: open_clips())
	(%TreadmillConsole as E_InteractableObject).interacted.connect(func(_e: Entity) -> void: open_states())
	(%MatConsole as E_InteractableObject).interacted.connect(func(_e: Entity) -> void: mat.lay_body())


func open_clips() -> Control:
	return _open(CLIP_SCREEN, stand)


func open_states() -> Control:
	return _open(STATE_SCREEN, treadmill)


## Экран в стеке UIManager с блоком ввода игрока — курсор и Esc оттуда же, что у дерева навыков.
func _open(scene: PackedScene, subject: Node3D) -> Control:
	var screen := scene.instantiate() as Control
	UIManager.push_blocking_screen(screen)
	screen.setup(subject, polygon)
	return screen
