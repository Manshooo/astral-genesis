class_name C_BodyVisual
extends Component
## Визуал захваченного тела на душе-риге: S_BodySnatch вешает, O_BodyVisual применяет, O_ExpelFromBody снимает.
## Меш переносится на риг, сам узел тела поглощён. Вики: [[Захват тела]].

## Меш и материал, снятые с тела.
@export var mesh: Mesh
@export var material_override: Material

## Трансформ меша относительно корня тела (подошвы): у рига origin в центре коллайдера, поэтому едет с мешем.
## Заодно переносит масштаб и сдвиг сцены тела.
@export var mesh_transform: Transform3D

## На сколько origin рига выше подошвы в этом облике (то же, что C_BodyForm.foot_offset). Едет с обликом: порядок
## вызова наблюдателей задаёт очередь команд, а E_Player.foot_offset() дал бы габарит, который риг ещё носит. ZERO — габарита нет.
@export var foot_offset: Vector3

## Что вернуть при развоплощении, включая трансформ; заполняет O_BodyVisual (вид БФЖ — в e_player.tscn).
@export var restore_mesh: Mesh
@export var restore_material: Material
@export var restore_transform: Transform3D
