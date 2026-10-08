# res://src/resources/rs_graphics_preset.gd
## Один уровень качества графики: разрешение, тени, сглаживание — одним
## пакетом, а не отдельными настройками. Масштаб разрешения умышленно лежит
## здесь же, а не отдельным ползунком: на слабом железе он идёт в связке с
## остальным качеством, а не крутится независимо от него. Vsync сюда НЕ входит:
## это про то, рвутся ли кадры на конкретном мониторе, а не про качество
## картинки — тянуть его за пресетом смысла нет (см. RS_Settings.vsync_enabled).
class_name RS_GraphicsPreset
extends Resource

enum AAMode {OFF, FXAA, MSAA_2X, MSAA_4X}

## Тени выключены — не ступень RS_ShadowLevel, а её отсутствие: атласы
## зануляются, лампы тень не отбрасывают. Свет ламп при этом проходит сквозь
## стены — это цена пункта, и подсказка в меню говорит о ней.
const SHADOWS_OFF := &"off"

## Ключ пресета ("low"/"medium"/"high") — то, что хранится в
## RS_Settings.graphics_preset_id и в SettingsManager.preset_by_id().
@export var id: StringName = &""
## Ключ перевода названия в списке пресетов (SETTINGS_PRESET_*): пункт списка
## переводится сам, данные хранят ключ, а не готовую строку.
@export var display_name: String = ""

@export_range(0.5, 1.5, 0.05) var render_scale: float = 1.0

## Ступень теней: id из RS_GraphicsPresetLibrary.shadow_levels или SHADOWS_OFF.
@export var shadow_quality: StringName = &"medium"

@export_group("Сглаживание")
@export var aa_mode: AAMode = AAMode.FXAA


## Раскатывает пресет на настройки игрока. Одно место на меню (выбор в списке) и
## на SettingsManager (сейв с именованным пресетом приводится к нынешнему
## пресету): поле, добавленное в пресет, иначе пришлось бы вписывать в двух
## местах, и одно из них забылось бы.
func apply_to(settings: RS_Settings) -> void:
	settings.render_scale = render_scale
	settings.shadow_quality = shadow_quality
	settings.aa_mode = aa_mode


## Совпадают ли настройки с пресетом по всем его полям — то есть не «Собственные».
func matches(settings: RS_Settings) -> bool:
	return (
		is_equal_approx(settings.render_scale, render_scale)
		and settings.shadow_quality == shadow_quality
		and settings.aa_mode == aa_mode
	)
