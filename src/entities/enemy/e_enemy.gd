# res://src/entities/enemy/e_enemy.gd
## Живая цель — бежит на воплощённого БФЖ и бьёт в упор (S_EnemyAI). Не тело:
## захватить его нельзя (нет C_BodySnatchable), и с трупами-целями захвата
## (E_Body) не путать — это разные сущности с разными задачами, хотя обе
## сделаны из monsters.glb.
##
## Корень — CharacterBody3D, а не StaticBody3D, как у E_Body: враг ходит, и
## только CharacterBody3D слушает C_Velocity через move_and_slide()
## (S_Movement). Слой коллизии — enemies, как у тел. Луч захвата
## (S_SnatchTargetDetector) проходит врага насквозь, поэтому тот не заслоняет
## настоящие цели у себя за спиной. Маска и почему враг упирается в игрока, а
## игрок во врага нет — docs «Конвенции проекта», §2.
@tool
class_name E_Enemy
extends Entity
