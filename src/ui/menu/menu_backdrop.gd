# res://src/ui/menu/menu_backdrop.gd
## Фон экрана меню: в забеге заволакивает мир шейдером, вне забега — глухой фон (menu_backdrop.gdshader); выбирает по UIManager.enabled. Материал в menu_backdrop.tscn,
## resource_local_to_scene: amount у каждого фона свой (настройки поверх паузы — два фона).
class_name UI_MenuBackdrop
extends ColorRect

## Вход заволакивания (§7: 220 мс, ease-out).
const FADE_IN := 0.22


func _ready() -> void:
	var shader_material := material as ShaderMaterial
	shader_material.set_shader_parameter(&"void_amount", 0.0 if UIManager.enabled else 1.0)

	# Поверх другого экрана мир уже заволочен — с нуля между двумя экранами проступил бы чистый кадр.
	if UIManager.has_screens():
		shader_material.set_shader_parameter(&"amount", 1.0)
		return
	shader_material.set_shader_parameter(&"amount", 0.0)
	create_tween().tween_property(shader_material, "shader_parameter/amount", 1.0, FADE_IN) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
