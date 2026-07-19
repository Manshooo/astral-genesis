# res://src/entities/body/e_body.gd
## Инертное тело/труп — первая цель захвата БФЖ. ИИ нет: тело статично, его задача —
## дать S_BodySnatch что вселить. Характеристики (C_Health, C_BodySnatchable)
## настраиваются через component_resources в сцене/инспекторе, а не в коде, чтобы
## пресеты тел тюнились дизайнером.
##
## Коллайдер лежит на слое enemies (layer_3, collision_layer = 1 << 2), куда смотрит
## луч захвата S_BodySnatch; в игрока и интерактивы луч не попадает.
@tool
class_name E_Body
extends Entity
