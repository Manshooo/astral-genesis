class_name RS_SkillBranch
extends Resource
## Ветка дерева навыков: подпись и цвет дорожки в graph-UI, данными в data/skill_tree.tres. Не обязательна: навык с неизвестной
## веткой всё равно попадёт в граф (иначе опечатка прятала бы навык насовсем).

## Цвет ветки, которую не описали; его же возвращает RS_SkillTree.branch_color.
const DEFAULT_COLOR := Color(0.62, 0.72, 0.85)

@export var id: StringName = &""
@export var display_name: String = ""
## Акцент дорожки: подложка, полоска на карточке, связи.
@export var color: Color = DEFAULT_COLOR
