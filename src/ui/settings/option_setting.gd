# res://src/ui/settings/option_setting.gd
## Настройка-список. Повесить на OptionButton, задать пункты в инспекторе
## (Items) и параллельным массивом option_values — какое значение настройки
## соответствует пункту с тем же индексом (в .tscn у enum-настроек это числа
## самого enum). Индексы должны совпадать: пункт N ↔ option_values[N].
class_name OptionSetting
extends OptionButton

@export var setting_key: String = ""
@export var option_values: Array = []

signal setting_changed(control: OptionSetting)

func _ready() -> void:
	item_selected.connect(_on_item_selected)

func get_setting_value() -> Variant:
	return option_values[selected] if selected >= 0 and selected < option_values.size() else null

func set_setting_value(v: Variant) -> void:
	var idx := option_values.find(v)
	select(idx if idx != -1 else 0)

func _on_item_selected(_idx: int) -> void:
	setting_changed.emit(self)
