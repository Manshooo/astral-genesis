class_name C_Interactable
extends Component

@export var action_name: StringName = &"interact"
## Подпись подсказки — ключ перевода (ui.csv); переводит HUD, клавиша вклеивается после.
@export var prompt_text: String
@export var enabled: bool = true
## Показывать ли в подсказке клавишу (false — запечатанная дверь «Прохода нет»).
@export var show_key_hint: bool = true

## Нужно ли ТЕЛО для использования: развоплощённый рычаг не повернёт. Двери помечены (развоплощённый
## заперт, пока не найдёт тело); порталы — нет; хаб стартует с телом в комнате.
@export var requires_body: bool = false
