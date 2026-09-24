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

## Ключ пресета ("low"/"medium"/"high") — то, что хранится в
## RS_Settings.graphics_preset_id и в SettingsManager.preset_by_id().
@export var id: StringName = &""
@export var display_name: String = ""

@export_range(0.5, 1.5, 0.05) var render_scale: float = 1.0

@export_group("Тени")
@export var shadows_enabled: bool = true
@export var shadow_atlas_size: int = 2048

@export_group("Сглаживание")
@export var aa_mode: AAMode = AAMode.FXAA
