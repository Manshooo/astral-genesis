class_name C_EnemyAI
extends Component
## Поведение врага: стоит, пока не заметил воплощённого БФЖ, гонится, ищет в последнем месте, бьёт в упор.
## Состояние — enum-поле, а не теги C_Idle/C_Chasing: нет риска взаимоисключающих тегов (см. [[GECS и правила движка]] про FSM).
## Числа авторские (в сцене врага); обзор и память — рантайм-поля без @export.

enum State {
	## Стоит: цели нет или не заметил.
	IDLE,
	## Видит цель и идёт на неё (в упор — бьёт).
	CHASING,
	## Потерял цель из виду и идёт на место, где видел её последний раз; дойдя —
	## стоит там [member linger_time] и сдаётся.
	SEARCHING,
}

# --- Бой ---

## Дальность обзора: дальше этого врага цель не замечает и не удерживает.
@export var aggro_range: float = 10.0
## Дистанция, с которой враг бьёт вместо того, чтобы бежать дальше.
@export var attack_range: float = 1.8
@export var attack_damage: float = 15.0
## Пауза между ударами, с.
@export var attack_interval: float = 1.0

# --- Обнаружение ---

## Полный угол обзора, градусов. Встревоженный враг конусом не ограничен.
@export_range(10.0, 360.0, 1.0) var view_angle: float = 110.0
## Ближе этого цель замечается и за спиной (нужна линия видимости), м.
@export var awareness_range: float = 2.0
## Высота глаз над ногами, м (начало луча обзора).
@export var eye_height: float = 1.6
## Период проверки обзора, с: луч не каждый кадр, иначе расход на ровном месте.
@export var sight_interval: float = 0.2
## Что закрывает обзор: стены и двери; решётки (permeable) не закрывают.
@export_flags_3d_physics var sight_mask: int = 1 | (1 << 4)

# --- Память ---

## Сколько враг стоит там, где видел цель, прежде чем сдаться, с.
@export var linger_time: float = 4.0
## Потолок поиска, с: путь к месту может быть закрыт.
@export var search_timeout: float = 15.0

# --- Путь ---

## Период перестроения пути по навмешу, с.
@export var repath_interval: float = 0.4
## Расстояние до точки пути (по горизонтали), с которого она пройдена, м.
@export var waypoint_reach: float = 0.6
## Расстояние до места последнего виденья, с которого оно достигнуто, м.
@export var arrive_distance: float = 1.0
## Шаблон навмеша по размеру врага (один из LayerNavigation.PROFILES): агент выше нужного выбрасывает из навмеша
## места под нависаниями. dev/enemy_nav_check сверяет покрытие капсулы.
@export var nav_profile: NavigationMesh = preload("res://data/enemy_navmesh.tres")
## Открывает ли враг двери. Навмеш запечён сквозь проёмы: при false враг дойдёт до полотна и встанет.
@export var opens_doors: bool = true

## Текущее состояние; пишет только S_EnemyAI.
@export var state: State = State.IDLE
## Сколько ждать до следующего удара, с (0 — можно бить).
@export var attack_cooldown_left: float = 0.0

# Рантайм-состояние обзора, памяти и пути — пишет только S_EnemyAI.

## Результат последней проверки обзора.
var sees_target := false
## Сколько осталось до следующей проверки обзора, с.
var sight_left := 0.0
## Сколько лучей обзора брошено за жизнь врага (проверки, профайлер).
var sight_rays := 0
## Где в последний раз видели цель (мировые координаты, у ног цели).
var last_seen_position := Vector3.ZERO
## Сколько осталось поиска, с (в состоянии SEARCHING).
var search_left := 0.0
## Дошёл ли враг до места последнего виденья.
var arrived := false
## Путь по навмешу к цели; пустой — навмеша нет, идём по прямой.
var path := PackedVector3Array()
var path_index := 0
var repath_left := 0.0
