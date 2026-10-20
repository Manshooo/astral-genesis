# res://src/entities/enemy/e_enemy.gd
## Живой враг: бежит на воплощённого БФЖ и бьёт в упор (S_EnemyAI). Не тело — захватить нельзя; вселяются в
## труп [member corpse_scene] (E_Body), который остаётся после смерти (O_EnemyDeath). Корень — CharacterBody3D (C_Velocity
## слушает move_and_slide). Луч захвата проходит врага насквозь, луч удара ловит. Вики: [[Конвенции проекта]] §2.
@tool
class_name E_Enemy
extends Entity

## Труп после смерти — сцена E_Body: сейв восстанавливает тело по её пути. Пусто — враг умирает без трупа.
@export var corpse_scene: PackedScene


## Класс угрозы врага L0..L5 — класс его трупа (второго числа нет). 0, если трупа нет.
func threat_class() -> int:
	if corpse_scene == null:
		return 0
	return E_Body.class_of_scene(corpse_scene.resource_path)
