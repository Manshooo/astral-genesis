# res://src/resources/rs_graphics_preset.gd
## Уровень качества графики пакетом (разрешение, тени, сглаживание). Масштаб разрешения здесь же; Vsync не входит —
## про монитор, не про качество (RS_Settings.vsync_enabled). Вики: [[Конвенции проекта]] §6.
class_name RS_GraphicsPreset
extends Resource

enum AAMode {OFF, FXAA, MSAA_2X, MSAA_4X}

## Тени выключены — не ступень, а её отсутствие: атласы занулены; свет ламп проходит сквозь стены (подсказка в меню говорит).
const SHADOWS_OFF := &"off"

## Ключ пресета ("low"/"medium"/"high") — RS_Settings.graphics_preset_id.
@export var id: StringName = &""
## Ключ перевода названия (SETTINGS_PRESET_*).
@export var display_name: String = ""

@export_range(0.5, 1.5, 0.05) var render_scale: float = 1.0

## Ступень теней: id из RS_GraphicsPresetLibrary.shadow_levels или SHADOWS_OFF.
@export var shadow_quality: StringName = &"medium"
## Ступень экранных эффектов: id из RS_GraphicsPresetLibrary.effects_levels.
@export var screen_effects: StringName = &"medium"
## Свечение: в пресете — на встроенной графике размытие заметная доля кадра.
@export var glow_enabled: bool = true

@export_group("Сглаживание")
@export var aa_mode: AAMode = AAMode.FXAA


## Раскатывает пресет на настройки: одно место на меню и на SettingsManager (поле не забудется в одном из двух).
func apply_to(settings: RS_Settings) -> void:
	settings.render_scale = render_scale
	settings.shadow_quality = shadow_quality
	settings.screen_effects = screen_effects
	settings.glow_enabled = glow_enabled
	settings.aa_mode = aa_mode


## Совпадают ли настройки с пресетом по всем полям (не «Собственные»).
func matches(settings: RS_Settings) -> bool:
	return (
		is_equal_approx(settings.render_scale, render_scale)
		and settings.shadow_quality == shadow_quality
		and settings.screen_effects == screen_effects
		and settings.glow_enabled == glow_enabled
		and settings.aa_mode == aa_mode
	)
