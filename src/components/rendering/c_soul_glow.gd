# res://src/components/rendering/c_soul_glow.gd
# Свечение души: слабая лампа у глаз игрока — на дне мир гасит свет по глубине (RS_DepthLight), и душа светит сама,
# тем тусклее, чем ближе распад. Числа — данные сцены игрока; цвет — палитра HUD (UI_HudMood), как у дуги распада.
class_name C_SoulGlow
extends Component

## Лампа свечения относительно сущности игрока (под камерой — едет на уровне глаз тела).
@export var light_path: NodePath = ^"Camera3D/SoulGlow"
## Энергия при спокойном запасе.
@export_range(0.0, 4.0, 0.01) var energy_full: float = 0.6
## Энергия на пустом запасе; не ноль — иначе в провале не найти выхода.
@export_range(0.0, 4.0, 0.01) var energy_faded: float = 0.12

## Доля янтаря в цвете (0 — душа, 1 — тело); перетекает за UI_DecayArc.TINT_SECONDS.
var body_mix: float = 0.0
