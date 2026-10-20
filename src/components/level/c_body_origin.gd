class_name C_BodyOrigin
extends Component
## Стабильный id авторского тела в комплексе ("<узел графа>/<путь в комнате>"): штампует RunManager при
## спавне комнаты. Нужен сейву (RS_WorldSave.consumed_body_ids), чтобы комната из сида не подсунула дубликат поглощённого тела.

## "<id узла графа>/<путь узла в комнате>", например "hub_0/Body".
@export var body_id: StringName = &""
