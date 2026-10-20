class_name C_Embodied
extends Component
## БФЖ сейчас во плоти (нет компонента = призрак, тикает C_Lifespan). Несёт путь к СЦЕНЕ тела — из неё
## после загрузки восстанавливается облик; меш в сейв не пишется (E_Body.visual_of).

## Сцена занятого тела; заполняет S_BodySnatch. Пустая строка — навесили в обход захвата.
@export var body_scene_path: String = ""
