## GDT_Ui — фабрики контролов инструментов: настройки, которые легко забыть (грабли №3 и №5), сделаны один раз.
## [[Редакторские инструменты]]. Только статика.
@tool
extends RefCounted

## Ширина для минимальной высоты переносящихся подписей: без неё Label меряет себя по ~17 px.
const WRAP_WIDTH := 240


static func button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(handler)
	return b


## Обычная подпись поля — переносов не ждём, тултипа ей не нужно.
static func label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


## Однострочная подпись с многоточием. MOUSE_FILTER_STOP обязателен: иначе tooltip_text не работает
## (грабли №3 и №5).
static func ellipsis_label(text := "") -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	return l


## Заголовок раздела — алиас ellipsis_label ради читаемости вызова.
static func section_label(text := "") -> Label:
	return ellipsis_label(text)


## Строка статуса внизу инструмента: та же однострочная подпись, приглушённая.
static func status_label() -> Label:
	var l := ellipsis_label()
	l.modulate = Color(1, 1, 1, 0.7)
	return l


## Переносящаяся подпись. custom_minimum_size.x обязателен — см. WRAP_WIDTH.
static func wrap_label(text: String, wrap_width := WRAP_WIDTH) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(wrap_width, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	return l


## Текст обрезается многоточием, поэтому целиком он кладётся в подсказку —
## иначе конец сообщения (обычно путь ресурса) прочитать негде.
static func set_status(target: Label, text: String) -> void:
	target.text = text
	target.tooltip_text = text


## Отчёт с разметкой: «Проверить сцены» и «Прогон сидов» печатают одинаково.
static func report_label(min_height: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.selection_enabled = true
	r.custom_minimum_size = Vector2(0, min_height)
	r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return r


## Распорка, отжимающая соседей к краям панели инструментов.
static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


## Диалог с одним полем ввода.
static func text_dialog(title: String, on_confirmed: Callable) -> ConfirmationDialog:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	var edit := LineEdit.new()
	edit.custom_minimum_size = Vector2(280, 0)
	dialog.add_child(edit)
	dialog.register_text_enter(edit)
	dialog.confirmed.connect(on_confirmed)
	return dialog


## Поле ввода диалога, заведённого text_dialog().
static func dialog_edit(dialog: ConfirmationDialog) -> LineEdit:
	for child: Node in dialog.get_children():
		if child is LineEdit:
			return child as LineEdit
	return null


## Открывает диалог с подставленным текстом и выделяет его — «Переименовать»
## и «Новый» одинаково ждут, что имя можно сразу перепечатать.
static func popup_text_dialog(dialog: ConfirmationDialog, title: String, text: String) -> void:
	dialog.title = title
	var edit := dialog_edit(dialog)
	if edit == null:
		return
	edit.text = text
	dialog.popup_centered(Vector2i(340, 90))
	edit.grab_focus()
	edit.select_all()
