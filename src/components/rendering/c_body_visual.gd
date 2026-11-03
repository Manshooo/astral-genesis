class_name C_BodyVisual
extends Component
## Визуал захваченного тела на душе-риге: S_BodySnatch вешает, O_BodyVisual применяет, O_ExpelFromBody снимает.
## Облик тела — сцена (SK_*.tscn, узел Visual тела): риг надевает её инстанс со скелетом и клипами. Тела, ещё не
## переведённые на свой .glb, отдают один меш. Сам узел тела поглощён. Вики: [[Захват тела]].

## Сцена облика; null — тело отдаёт один меш (mesh/material_override).
@export var scene: PackedScene

## Как анимирован облик: дерево и библиотеки AnimationTree тела. Риг ставит их на свой узел BodyAnimation.
@export var tree_root: AnimationRootNode
@export var libraries: Dictionary[StringName, AnimationLibrary] = {}

## Материалы, которыми сцена тела перекрасила меши облика (тон L5 на общем SK_hound): имя меша → материал.
@export var material_overrides: Dictionary[StringName, Material] = {}

## Руки-муляж тела (E_Body.fp_arms_scene): риг вешает их на камеру. null — рук в кадре нет.
@export var fp_arms: PackedScene

## Меш и материал, снятые с тела, — у тел без сцены облика.
@export var mesh: Mesh
@export var material_override: Material

## Трансформ облика относительно корня тела (подошвы): у рига origin в центре коллайдера, поэтому едет с обликом.
## Заодно переносит масштаб, сдвиг и доворот модели в сцене тела.
@export var mesh_transform: Transform3D

## На сколько origin рига выше подошвы в этом облике (то же, что C_BodyForm.foot_offset). Едет с обликом: порядок
## вызова наблюдателей задаёт очередь команд, а E_Player.foot_offset() дал бы габарит, который риг ещё носит. ZERO — габарита нет.
@export var foot_offset: Vector3

## Что вернуть при развоплощении, включая трансформ; заполняет O_BodyVisual. У души своего меша нет (её облик —
## C_SoulCloud), поэтому restore_mesh законно null.
@export var restore_mesh: Mesh
@export var restore_material: Material
@export var restore_transform: Transform3D
## restore_* уже сняты. Отдельный флаг: пустой restore_mesh не отличить от «ещё не снимали», и пересадка
## тело→тело запомнила бы меш прошлого тела вместо пустого слота души.
@export var restore_captured: bool = false
