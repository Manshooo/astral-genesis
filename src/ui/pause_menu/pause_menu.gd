# res://src/ui/pause_menu/pause_menu.gd
## Пауза «Отголосок» (§9 «Меню — спека»): мир заволакивается (UI_MenuBackdrop), пункты-мысли колонкой по центру.
extends UI_MenuScreen

const MENU_SCENE := "res://src/levels/menu_map/L_menu_map.tscn"
## Сколько держать отметку «Сохранено» на кнопке.
const SAVED_HINT_SECONDS := 1.5
## Пункты входят лесенкой, каждый на 30 мс позже (§7).
const ITEM_STAGGER := 0.03

const SAVE_ICON := preload("res://assets/ui/icons/save.svg")

@onready var save_button: UI_EchoButton = %Save
@onready var _items: VBoxContainer = %Column


func _ready() -> void:
	super._ready()
	_stagger_items()


## Лесенка входа пунктов: колонка проступает сверху вниз, как мысль.
func _stagger_items() -> void:
	var i := 0
	for item in _items.get_children():
		if not item is Control:
			continue
		var control := item as Control
		control.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_interval(i * ITEM_STAGGER)
		tween.tween_property(control, "modulate:a", 1.0, ENTER_TIME) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		i += 1


func _on_continue_pressed() -> void:
	UIManager.close_top()


## Ручное сохранение: распад тикает непрерывно — кнопка фиксирует запас на сейчас. Отклик обязателен, иначе выглядит сломанной.
func _on_save_pressed() -> void:
	if not RunManager.save_progress():
		_flash_save_button("PAUSE_SAVE_NOTHING", false)
		return
	_flash_save_button("PAUSE_SAVED", true)


func _on_settings_pressed() -> void:
	var settings_menu = load("res://src/ui/settings_menu/settings_menu.tscn").instantiate()
	UIManager.push_screen(settings_menu)


func _on_exit_to_menu_pressed() -> void:
	# Меню грузится в фоне, пока пункты гаснут; мир стоит, пока сцена не готова — иначе под размытием пустота.
	for node in _items.find_children("*", "Button", true, false):
		(node as Button).disabled = true
	var pressed := get_node_or_null(^"Content/Column/ToMenu") as UI_EchoButton
	if pressed:
		pressed.busy = true
	var menu := await SceneLoader.load_scene(get_tree(), MENU_SCENE)
	# Забег не заканчиваем, только фиксируем точку и отпускаем мир: RunManager переживёт сцену и не должен держать убитые комнаты.
	RunManager.leave_to_menu()
	UIManager.close_all()
	UIManager.enabled = false
	get_tree().change_scene_to_packed(menu)


## Подменяет подпись кнопки на время: удачное сохранение — сиреневым со значком дискеты, отказ — только словами. Таймер с process_always (на паузе обычный не тикал бы).
func _flash_save_button(key: String, saved: bool) -> void:
	var original := save_button.text
	if save_button.disabled:
		return  # отметка уже висит — не наслаиваем
	save_button.text = key
	save_button.disabled = true
	if saved:
		save_button.marked = true
		save_button.icon = SAVE_ICON
		save_button.add_theme_color_override(&"font_disabled_color", UI_HudMood.SOUL)
	await get_tree().create_timer(SAVED_HINT_SECONDS, true).timeout
	if not is_instance_valid(save_button):
		return  # меню успели закрыть
	save_button.text = original
	save_button.icon = null
	save_button.marked = false
	save_button.remove_theme_color_override(&"font_disabled_color")
	save_button.disabled = false
