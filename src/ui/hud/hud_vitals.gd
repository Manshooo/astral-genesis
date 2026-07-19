# res://src/ui/hud/hud_vitals.gd
## Панель витальных показателей БФЖ в HUD:
##   - запас распада (C_Lifespan) — ВСЕГДА (у призрака тикает вниз, во плоти на паузе);
##   - HP текущего тела (C_Health) — ТОЛЬКО во плоти (есть C_Embodied): у призрака
##     тела, а значит и C_Health, нет.
## Значения меняются непрерывно (таймер распада, урон по телу), поэтому опрашиваем
## игрока каждый кадр — событийная модель тут проигрывает простому поллингу.
class_name UI_HudVitals
extends VBoxContainer

@onready var _lifespan_bar: ProgressBar = $LifespanRow/LifespanBar
@onready var _lifespan_value: Label = $LifespanRow/LifespanValue
@onready var _health_row: HBoxContainer = $HealthRow
@onready var _health_bar: ProgressBar = $HealthRow/HealthBar
@onready var _health_value: Label = $HealthRow/HealthValue


func _process(_delta: float) -> void:
	var player := _get_player()
	if player == null:
		# Игрока ещё/уже нет (загрузка сцены, смерть) — прячем панель целиком.
		visible = false
		return
	visible = true
	_update_lifespan(player)
	_update_health(player)


func _update_lifespan(player: Entity) -> void:
	var life := player.get_component(C_Lifespan) as C_Lifespan
	if life == null:
		return
	_lifespan_bar.max_value = life.max_duration
	_lifespan_bar.value = life.current
	_lifespan_value.text = "%.0f с" % ceilf(life.current)


func _update_health(player: Entity) -> void:
	# HP тела показываем только во плоти — у развоплощённой души C_Health нет.
	var embodied := player.has_component(C_Embodied)
	_health_row.visible = embodied
	if not embodied:
		return
	var hp := player.get_component(C_Health) as C_Health
	if hp == null:
		return
	_health_bar.max_value = hp.maximum
	_health_bar.value = hp.current
	_health_value.text = "%.0f" % ceilf(hp.current)


func _get_player() -> Entity:
	if ECS.world == null:
		return null
	return ECS.world.query.with_all([C_PlayerInput]).execute_one()
