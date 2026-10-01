# res://src/ui/hud/hud_screen_fx.gd
## Эффекты экрана «Отголоска» (§8, §11 «HUD — спека»): то, что прежде
## показывали полосы, теперь проступает в самом мире.
##   - распад того кармана, что убывает: у души — холодная виньетка и уход в
##     серое с постоянной слабой базой («я — душа»), у тела — тёплая и в сепию,
##     без базы (пустой карман тела не убивает, а выбрасывает душу);
##   - здоровье тела — только кровь по краю; удар — вспышка, потемнение, тряска;
##   - вселение и выход — волна от краёв цветом нового кармана.
##
## Узел только считает юниформы по формулам спеки, рисует hud_screen_fx.gdshader.
## Слой холста ниже обводки и HUD (см. hud.tscn): распад не должен искажать ни
## текст, ни контур интерактива — их обязано быть видно и на пороге.
class_name UI_HudScreenFx
extends ColorRect

## Удар по телу: импульсы и их постоянные времени (§6).
const HIT_DARK := 0.55
const HIT_DARK_TAU := 0.35
## Красная вспышка — по силе удара: полная от удара на HIT_FULL_SHARE
## максимума HP и больше, у мелкого — не меньше HIT_MIN_SHARE силы. Одинаковая
## вспышка на царапину и на полтела не говорила бы, насколько было больно.
const HIT_RED := 0.5
const HIT_RED_TAU := 0.5
const HIT_FULL_SHARE := 0.25
const HIT_MIN_SHARE := 0.2
## Меньше 5 px спеки — решено 01.10 при приёмке: тряска не должна спорить с
## прицелом, удар и так виден вспышкой.
const SHAKE_PX := 3.0
const SHAKE_TAU := 0.18
## Волна вселения и выхода.
const SHINE := 0.7
const SHINE_TAU := 0.3
## Смена тона души ↔ тела идёт вместе с цветом дуги.
const TINT_SECONDS := 0.25
## За сколько прежняя раскладка пятен крови перетекает в новую после удара:
## дольше вспышки удара, чтобы смена не читалась скачком.
const BLOT_SECONDS := 0.4
## Насколько удар поворачивает пятна, радианы в обе стороны: небольшой поворот
## меняет узор, а сильный крутил бы всю кайму заметно глазу.
const BLOT_TURN := 0.6

## Последние выставленные значения — открыты для проверки кривых без пикселей.
var params: Dictionary = {}

var _body_mix := 0.0
var _last_pocket := false
var _has_pocket_state := false
var _hit_time := -INF
## Сила последнего удара 0…1 — множитель красной вспышки.
var _hit_strength := 1.0
var _shine_time := -INF
var _shine_color := UI_HudMood.SOUL
var _listener: _HitListener
var _listener_world: World
## Раскладки пятен крови (сдвиг x, сдвиг y, поворот) — до удара и после.
var _blot_from := Vector3.ZERO
var _blot_to := Vector3.ZERO
var _blot_time := -INF
var _rng := RandomNumberGenerator.new()


## Удар по игроку. Отдельный наблюдатель, а не опрос HP: падение HP врёт — тем
## же выглядят смена тела и потолок, урезанный снятием перка, — а событие урона
## S_Health шлёт ровно на удар (и для того его и шлёт).
class _HitListener:
	extends Observer

	var on_hit: Callable

	func query() -> QueryBuilder:
		return q.with_all([C_Health, C_PlayerInput]).on_event(&"damage_dealt")

	func each(_event: Variant, entity: Entity, payload: Variant = null) -> void:
		if not on_hit.is_valid():
			return
		# Доля урона — от эффективного потолка: перк на HP делает тот же удар
		# слабее и на экране.
		var share := 1.0
		var health := entity.get_component(C_Health) as C_Health
		if payload is S_Health.Damage and health:
			share = (payload as S_Health.Damage).amount / maxf(health.effective_maximum(entity), 0.001)
		on_hit.call(share)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ECS.world:
		_listen(ECS.world)
	ECS.world_changed.connect(_on_world_changed)


func _exit_tree() -> void:
	_unlisten()


func _on_world_changed(world: World) -> void:
	_unlisten()
	_has_pocket_state = false
	_hit_time = -INF
	_shine_time = -INF
	if world:
		_listen(world)


## Наблюдатель живёт в мире, а не в HUD: события доставляет только мир. Мир
## удаляет его вместе с собой, поэтому снимаем сами лишь тогда, когда HUD уходит
## раньше мира.
func _listen(world: World) -> void:
	_listener = _HitListener.new()
	_listener.name = "HudHitListener"
	_listener.on_hit = hit
	world.add_observer(_listener)
	_listener_world = world


func _unlisten() -> void:
	if is_instance_valid(_listener_world) and is_instance_valid(_listener):
		_listener_world.remove_observer(_listener)
	_listener = null
	_listener_world = null


## [param share] — доля максимума HP, которую снял удар.
func hit(share: float = 1.0, t: float = UI_HudMood.now()) -> void:
	_hit_time = t
	_hit_strength = clampf(share / HIT_FULL_SHARE, HIT_MIN_SHARE, 1.0)
	# Каждый удар перекладывает пятна: один узор на весь забег выдавал бы
	# текстуру. Перетекание не дорисовано — начинаем с той раскладки, что уже
	# преобладает; рывок прячет вспышка удара.
	_blot_from = _blot_to if _blot_mix(t) >= 0.5 else _blot_from
	_blot_to = Vector3(_rng.randf(), _rng.randf(), _rng.randf_range(-BLOT_TURN, BLOT_TURN))
	_blot_time = t


func _blot_mix(t: float) -> float:
	return clampf((t - _blot_time) / BLOT_SECONDS, 0.0, 1.0)


func _process(delta: float) -> void:
	update_params(UI_HudMood.read_vitals(E_Player.find()), UI_HudMood.now(), delta)
	var shader := material as ShaderMaterial
	if shader == null:
		return
	for key: String in params:
		shader.set_shader_parameter(key, params[key])
	# Без эффектов полноэкранный проход ничего не меняет — не гоняем его зря.
	visible = (
		params.vignette > 0.001 or params.desaturation > 0.001 or params.blood > 0.001
		or params.edge_dark > 0.001 or params.shine > 0.001
	)


## Кривые §8 — отдельно от записи в шейдер, чтобы проверка могла их спросить.
func update_params(vitals: UI_HudMood.Vitals, t: float, delta: float) -> void:
	if vitals == null:
		params = _calm()
		return

	if _has_pocket_state and vitals.body_pocket != _last_pocket:
		_shine_time = t
		_shine_color = UI_HudMood.BODY if vitals.body_pocket else UI_HudMood.SOUL
	_last_pocket = vitals.body_pocket
	_has_pocket_state = true
	_body_mix = move_toward(_body_mix, 1.0 if vitals.body_pocket else 0.0, delta / TINT_SECONDS)

	var soul_d := UI_HudMood.decay(vitals.soul)
	var body_d := UI_HudMood.decay(vitals.body) if vitals.body_pocket else 0.0
	var soul_vignette := (0.12 + 0.60 * soul_d) * _beat_boost(soul_d, t)
	var body_vignette := 0.60 * body_d * _beat_boost(body_d, t)
	var d := lerpf(soul_d, body_d, _body_mix)

	var since_hit := t - _hit_time
	var hit_red := HIT_RED * _hit_strength * exp(-since_hit / HIT_RED_TAU) if vitals.has_health else 0.0
	var shake := SHAKE_PX * exp(-since_hit / SHAKE_TAU) if vitals.has_health else 0.0
	var blood := 0.0
	if vitals.has_health:
		blood = 0.70 * UI_HudMood.sstep(0.45, 0.10, vitals.health) + hit_red

	params = {
		vignette = clampf(lerpf(soul_vignette, body_vignette, _body_mix), 0.0, 1.0),
		vignette_color = UI_HudMood.DECAY_TINT.lerp(UI_HudMood.BODY_TINT, _body_mix),
		desaturation = lerpf(0.15 + 0.70 * soul_d, 0.70 * body_d, _body_mix),
		desat_tint = Color.WHITE.lerp(UI_HudMood.BODY_SEPIA, _body_mix),
		distortion_px = 4.0 * d * d,
		chroma_px = 2.5 * d * d,
		blood = clampf(blood, 0.0, 1.0),
		edge_dark = HIT_DARK * exp(-since_hit / HIT_DARK_TAU) if vitals.has_health else 0.0,
		shake_px = shake * Vector2(UI_HudMood.noise(t * 37.0, 1.0), UI_HudMood.noise(t * 41.0, 2.3)),
		shine = SHINE * exp(-(t - _shine_time) / SHINE_TAU),
		shine_color = _shine_color,
		blot_from = _blot_from,
		blot_to = _blot_to,
		blot_mix = _blot_mix(t),
	}


## Виньетка бьётся в такт сердцу только за серединой распада — раньше пульс
## превращал бы спокойный фон в постоянную тревогу.
static func _beat_boost(d: float, t: float) -> float:
	return 1.0 + 0.35 * UI_HudMood.beat(d, t) if d > 0.35 else 1.0


## Игрока нет (загрузка, экран смерти) — экран чистый.
static func _calm() -> Dictionary:
	return {
		vignette = 0.0, vignette_color = UI_HudMood.DECAY_TINT, desaturation = 0.0,
		desat_tint = Color.WHITE, distortion_px = 0.0, chroma_px = 0.0, blood = 0.0,
		edge_dark = 0.0, shake_px = Vector2.ZERO, shine = 0.0, shine_color = UI_HudMood.SOUL,
		blot_from = Vector3.ZERO, blot_to = Vector3.ZERO, blot_mix = 1.0,
	}
