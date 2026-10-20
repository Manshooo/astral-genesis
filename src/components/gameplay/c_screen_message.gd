class_name C_ScreenMessage
extends Component
## Запрос к презентации: короткая строка поверх HUD. Вешается на игрока только через show_on(),
## рисует hud_message.gd, снимает S_ScreenMessage по таймеру.

## Ключ перевода или готовая строка — HUD прогоняет через tr().
@export var text: String = ""
## Секунд до снятия; равно времени показа (UI_HudMessage.TOTAL).
@export var remaining: float = 2.9


## Показать строку на target. Компонент ПЕРЕСОЗДАЁТСЯ: прямая запись в поля миру не сигналится.
## [param cmd] — буфер системы внутри прохода (правило v9); без него — только вне прохода ECS.
static func show_on(target: Entity, line: String, cmd: CommandBuffer = null) -> void:
	if target == null:
		return
	var message := C_ScreenMessage.new()
	message.text = line
	if cmd:
		if target.has_component(C_ScreenMessage):
			cmd.remove_component(target, C_ScreenMessage)
		cmd.add_component(target, message)
	else:
		if target.has_component(C_ScreenMessage):
			target.remove_component(C_ScreenMessage)
		target.add_component(message)
