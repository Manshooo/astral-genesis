# res://src/ui/menu/menu_backdrop.gd
## Фон экрана меню вместо прежних Panel-подложек: в забеге заволакивает мир
## шейдером, вне забега — глухой фон (menu_backdrop.gdshader). Сам решает,
## какой из двух, по UIManager.enabled — тот же признак «мы в забеге», что
## решает, захватывать ли курсор, поэтому экрану настроек не нужно знать, откуда
## его открыли.
##
## Материал — в menu_backdrop.tscn, экраны ставят фон экземпляром этой сцены.
## У материала resource_local_to_scene: amount анимируется у каждого фона свой,
## а настройки поверх паузы — два фона сразу; общий материал дёрнул бы оба.
class_name UI_MenuBackdrop
extends ColorRect

## Вход заволакивания (§7: 220 мс, ease-out).
const FADE_IN := 0.22


func _ready() -> void:
	var shader_material := material as ShaderMaterial
	shader_material.set_shader_parameter(&"void_amount", 0.0 if UIManager.enabled else 1.0)

	# Поверх другого экрана (настройки над паузой) мир уже заволочен: нарастай
	# фон с нуля, между двумя экранами на миг проступил бы чистый кадр.
	if UIManager.has_screens():
		shader_material.set_shader_parameter(&"amount", 1.0)
		return
	shader_material.set_shader_parameter(&"amount", 0.0)
	create_tween().tween_property(shader_material, "shader_parameter/amount", 1.0, FADE_IN) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
