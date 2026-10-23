# Звук распада игрока: петля byProd, которая звучит, пока убывающий карман ниже порога дуги HUD, и тем
# напряжённее, чем ближе распад. Данные сцены игрока, как C_SoulGlow; ведёт S_DecaySound. Вики: [[Звук]] §3б.
class_name C_DecaySound
extends Component

## Зацикленное событие распада.
@export var event_path: String = "event:/sfx/decay"
## Float-параметр события, в который уходит напряжение; пустой — петля без параметра.
@export var intensity_parameter: String = "Intensity"
## Напряжение у порога, где петля только вступает.
@export var intensity_calm: float = 1.0
## Напряжение на пустом кармане.
@export var intensity_max: float = 1.6
## За сколько секунд петля проступает, перейдя порог вниз: гул из ниоткуда читался бы как сбой, а не как распад.
@export var fade_in: float = 1.5
## За сколько секунд петля гаснет, когда запас снова над порогом.
@export var fade_out: float = 1.0

## Живой ByProdEventInstance петли; null — петля молчит. Тип Object: рантайма byProd может не быть, а ссылка
## на класс валит парсер (как C_Footsteps.loop_instance).
var instance: Object = null
