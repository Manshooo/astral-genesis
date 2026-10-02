# res://src/ui/menu/menu_screen.gd
## Общее у экранов меню «Отголосок»: вход и выход (§7 «Меню — спека») и фокус с
## клавиатуры, который появляется по первой же стрелке.
##
## Фокус не ставится при открытии намеренно: точка души у первого пункта значит
## «клавиатура здесь», и игроку с мышью она висела бы на пункте, на который он
## не смотрит. Поэтому первая стрелка или Tab, пока фокуса нет, только ставит его
## на [member first_focus] — дальше навигация штатная, по соседям.
class_name UI_MenuScreen
extends Control

## Вход экрана: проявление и подъём на 4 px (260 мс, ease-out).
const ENTER_TIME := 0.26
const ENTER_RISE := 4.0
## Выход: гаснет за 160 мс (ease-in), затем узел удаляется.
const EXIT_TIME := 0.16

## Пункт, на который встаёт фокус с клавиатуры, пока его нет.
@export var first_focus: Control
## Что поднимается при входе. Не весь экран: фон-заволакивание растянут на
## весь экран и, сдвинутый на 4 px, открыл бы полосу чистого мира сверху.
@export var content: Control

var _enter_tween: Tween


func _ready() -> void:
	_play_enter()
	# Экран под открытым поверх (настройки над паузой) прячется и показывается
	# снова — возвращение в него тоже вход, иначе он возникал бы скачком.
	visibility_changed.connect(_on_visibility_changed)


func _on_visibility_changed() -> void:
	if visible:
		_play_enter()


func _unhandled_input(event: InputEvent) -> void:
	if first_focus == null or not first_focus.is_visible_in_tree():
		return
	if get_viewport().gui_get_focus_owner() != null:
		return
	for action: StringName in [&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_focus_next", &"ui_focus_prev"]:
		if event.is_action_pressed(action):
			first_focus.grab_focus()
			get_viewport().set_input_as_handled()
			return


func _play_enter() -> void:
	if _enter_tween:
		_enter_tween.kill()
	modulate.a = 0.0
	_enter_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_enter_tween.tween_property(self, "modulate:a", 1.0, ENTER_TIME)
	if content:
		content.position.y = ENTER_RISE
		_enter_tween.tween_property(content, "position:y", 0.0, ENTER_TIME)


## Уход с экрана: UIManager уже снял его со стека, здесь он только гаснет. Твин
## от дерева, а не от узла: узел выключается, чтобы во время угасания не ловить
## клики, а твин узла остановился бы вместе с ним.
func play_exit() -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if focus and is_ancestor_of(focus):
		focus.release_focus()
	process_mode = Node.PROCESS_MODE_DISABLED
	var tween := get_tree().create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(self, "modulate:a", 0.0, EXIT_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)
