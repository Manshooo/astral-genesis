# res://src/ui/hud/hud_vitals.gd
## Панель витальных показателей БФЖ в HUD. Три строки, и они про разное:
##   - «Распад» — СОБСТВЕННЫЙ запас души (C_Lifespan.current). Во плоти он не
##     тикает: пока душа в теле, время платится из кармана тела. Может уходить за
##     максимум — излишек принесён из тела при добровольном выходе;
##   - «Запас тела» — карман текущего тела (C_BodyDecay), ТОЛЬКО во плоти. Это
##     та шкала, которая во плоти и убывает;
##   - «Тело» — HP текущего тела (C_Health), тоже только во плоти.
## Значения меняются непрерывно, поэтому опрашиваем игрока каждый кадр —
## событийная модель тут проигрывает простому поллингу.
class_name UI_HudVitals
extends VBoxContainer

@onready var _lifespan_bar: ProgressBar = $LifespanRow/LifespanBar
@onready var _lifespan_value: Label = $LifespanRow/PanelContainer2/LifespanValue
@onready var _body_life_row: HBoxContainer = $BodyLifeRow
@onready var _body_life_bar: ProgressBar = $BodyLifeRow/BodyLifeBar
@onready var _body_life_value: Label = $BodyLifeRow/PanelContainer2/BodyLifeValue
@onready var _health_row: HBoxContainer = $HealthRow
@onready var _health_bar: ProgressBar = $HealthRow/HealthBar
@onready var _health_value: Label = $HealthRow/PanelContainer2/HealthValue


func _process(_delta: float) -> void:
	var player := _get_player()
	if player == null:
		# Игрока ещё/уже нет (загрузка сцены, смерть) — прячем панель целиком.
		visible = false
		return
	visible = true

	_update_lifespan(player)
	_update_body_lifespan(player)
	_update_health(player)


## Собственный запас души. Шкала упирается в максимум, а подпись говорит правду:
## запас МОЖЕТ его превышать (излишек, вынесенный из тела), и растягивать ради
## этого саму шкалу — врать про то, где «нормальный полный».
func _update_lifespan(player: Entity) -> void:
	var life := player.get_component(C_Lifespan) as C_Lifespan
	if life == null:
		return
	# Потолок — эффективный, а не авторский: перк на запас должен быть виден
	# именно шкалой, иначе прокачка читается как «ничего не изменилось».
	var maximum := life.effective_max(player)
	_lifespan_bar.max_value = maximum
	_lifespan_bar.value = minf(life.current, maximum)

	var overflow := life.overflow(player)
	if overflow > 0.0:
		# «60 +18 с» — видно и то, что запас полон, и сколько сверху. Излишек
		# утекает быстрее обычного, так что число будет заметно бежать.
		_lifespan_value.text = "%.0f +%.0f с" % [maximum, ceilf(overflow)]
	else:
		_lifespan_value.text = "%.0f с" % ceilf(life.current)


## Карман текущего тела: во плоти убывает именно он. Строку показываем по
## НАЛИЧИЮ кармана (C_BodyDecay), а не по флагу «во плоти»: карман приходит и
## уходит вместе с телом, и тело, которое укрытия не даёт, не должно рисовать
## пустую шкалу.
func _update_body_lifespan(player: Entity) -> void:
	var decay := player.get_component(C_BodyDecay) as C_BodyDecay
	_body_life_row.visible = decay != null
	if decay == null:
		return
	# max_value не должен быть нулём: тело без запаса дало бы деление на ноль
	# внутри ProgressBar и пустую шкалу вместо честного нуля.
	_body_life_bar.max_value = maxf(decay.effective_maximum(player), 0.001)
	_body_life_bar.value = decay.remaining
	_body_life_value.text = "%.0f с" % ceilf(decay.remaining)


## HP тела показываем только во плоти — у развоплощённой души C_Health нет.
func _update_health(player: Entity) -> void:
	var hp := player.get_component(C_Health) as C_Health
	_health_row.visible = hp != null
	if hp == null:
		return
	_health_bar.max_value = hp.effective_maximum(player)
	_health_bar.value = hp.current
	_health_value.text = "%.0f" % ceilf(hp.current)


func _get_player() -> Entity:
	if ECS.world == null:
		return null
	return ECS.world.query.with_all([C_PlayerInput]).execute_one()
