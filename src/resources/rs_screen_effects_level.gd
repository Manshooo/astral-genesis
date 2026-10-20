## Ступень «Эффекты освещения»: SSAO, SSIL, SSR (с «Ультра» — SDFGI) одним пунктом по цене. Ступень — потолок, не включатель:
## выключенное автором окружения она не включит (LevelEnvironment). «Выкл» — обычная ступень без флажков. Вики: [[Конвенции проекта]] §6.
class_name RS_ScreenEffectsLevel
extends Resource

## Ключ ступени — RS_Settings.screen_effects и пресеты.
@export var id: StringName = &""
## Ключ перевода пункта списка.
@export var display_name: String = ""
@export var ssao: bool = false
@export var ssil: bool = false
@export var ssr: bool = false
@export var sdfgi: bool = false
