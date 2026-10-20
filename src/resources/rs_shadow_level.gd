# res://src/resources/rs_shadow_level.gd
## Ступень «Тени»: атлас, мягкость краёв и дальность одним пунктом. «Выкл» ступенью не описан (RS_GraphicsPreset.SHADOWS_OFF).
## Вики: [[Конвенции проекта]] §6.
class_name RS_ShadowLevel
extends Resource

## Ключ ступени — RS_Settings.shadow_quality и пресеты.
@export var id: StringName = &""
## Ключ перевода пункта списка.
@export var display_name: String = ""
## Атлас теней (один на позиционные и направленные); степень двойки — промежуточное округлится вверх.
@export var atlas_size: int = 2048
## Фильтр мягких теней: число выборок на пиксель растёт со ступенью.
@export var soft_filter: RenderingServer.ShadowQuality = RenderingServer.SHADOW_QUALITY_SOFT_LOW
## Дальше скольких метров от камеры лампа тени не отбрасывает (distance_fade_shadow, ставит LevelLight); главная ручка цены.
@export var shadow_distance: float = 40.0
## Ячеек в каждой из четырёх четвертей атласа — ОДИНАКОВО во всех (лампа вне кадра иначе получала мельчайшую ячейку, тени рассыпались
## в квадраты). Не меньше 16: омни-лампа занимает ПАРУ соседних ячеек, при четырёх пара рвётся. Число ламп с тенью ограничено (ShadowBudget).
@export var cells_per_quadrant: Viewport.PositionalShadowAtlasQuadrantSubdiv = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_16

## Ячеек в четверти по значению Viewport.PositionalShadowAtlasQuadrantSubdiv.
const _CELLS := [0, 1, 4, 16, 64, 256, 1024]


## Сколько ламп разом в кадре может отбрасывать тень: четвертей четыре, омни-лампа — две ячейки.
func lamp_budget() -> int:
	return _CELLS[cells_per_quadrant] * 2
