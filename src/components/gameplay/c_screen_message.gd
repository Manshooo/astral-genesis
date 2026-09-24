class_name C_ScreenMessage
extends Component
## Запрос к презентации: показать игроку короткую строку поверх HUD.
## Логика вешает компонент, hud_message.gd его рисует, S_ScreenMessage снимает
## по истечении времени — тот же приём развязки, что C_Highlighted → O_OutlineVisual.
##
## Вешается на сущность игрока — только через show_on(), где и живёт правило
## повторного показа.

@export var text: String = ""
## Сколько секунд ещё показывать. Тикает S_ScreenMessage.
@export var remaining: float = 2.5


## Показать строку [param line] на [param target]. Компонент ПЕРЕСОЗДАЁТСЯ (remove+add), а не
## правится: прямая запись в поля миру не сигналится, и HUD не увидел бы нового
## текста. Раньше это было переписано в пяти местах, каждое — со своей копией
## этого же объяснения.
## [param cmd] — буфер системы, когда зовут изнутри её прохода (правило v9);
## без него правка прямая — законна только вне прохода ECS (call_deferred из
## S_InteractInput, обработка ввода).
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
