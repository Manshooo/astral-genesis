class_name C_SoulTrait
extends Component
## Базовый класс возможностей САМОЙ души (C_Flight, C_Phasing). Зеркало C_BodyTrait, но отдельный класс:
## трейты тела уезжают с телом, возможности души на время воплощения ЗАСЫПАЮТ. Снимает и возвращает O_SoulTraits
## СВЕЖИМИ копиями из component_resources сцены души (E_Player.soul_traits): заначка не пережила бы
## пересадку тело→тело (буфер коалесцирует remove+add C_Embodied). Авторить — в сцене души, не в define_components().


## Эффект «Бесплотности» в левой части HUD (UI_HudEffects): ключ перевода и значок; пустой ключ — не показывать.
@export var effect_key: StringName = &""
@export var effect_icon: Texture2D
