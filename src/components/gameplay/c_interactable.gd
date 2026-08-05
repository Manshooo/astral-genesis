class_name C_Interactable
extends Component

@export var action_name: StringName = &"interact"
@export var prompt_text: String
@export var enabled: bool = true
## Показывать ли в подсказке клавишу действия ("[F] Пройти"). false — для
## объектов, которые подсвечиваются и объясняют себя, но нажимать на них
## бессмысленно (напр. запечатанная дверь: «Прохода нет»).
@export var show_key_hint: bool = true
