## res://src/resources/rs_game_config.gd
## Конфиг разработчика (data/game_config.tres): баланс и физика, не пользовательские настройки (не user://, не черновик SettingsManager).
class_name RS_GameConfig
extends Resource

@export_group("FPS")
@export var pitch_limit: float = 1.4           ## ~80° в радианах

@export_group("Physics")
@export var gravity: float = 9.8

## Высота, ниже которой сущность считается провалившейся из мира, м (S_VoidFall).
@export var void_fall_depth: float = -100.0

# Числа полёта лежат в C_Flight на сцене e_player.tscn.

@export_group("Распад")
## Во сколько раз быстрее утекает запас СВЕРХ максимума души (излишек, принесённый из тела).
@export var lifespan_overflow_leak: float = 3.0
## Доля максимума души, что остаётся, если тело ПОГИБЛО (HP или время): остаток тела не переносится.
@export_range(0.0, 1.0) var lifespan_death_fraction: float = 0.1

## Секунд затемнения между потерей стабильности и итогами; мир всё это время живой (RunManager.die).
@export_range(0.0, 3.0) var death_fade_duration: float = 0.8

@export_group("Переходы")
## Вид перехода порталом: FADE — экран гаснет и проявляется, CURTAIN — шторка загрузки. F2 отладочного оверлея переключает на лету.
enum PortalTransition { FADE, CURTAIN }
@export var portal_transition: PortalTransition = PortalTransition.FADE
## Секунд гаснет и столько же проявляется при FADE.
@export_range(0.05, 2.0) var portal_fade_duration: float = 0.3

@export_group("Сохранение")
## Секунд между контрольными точками (RunManager._process): верхняя граница потерь при вылете.
@export_range(5.0, 120.0) var autosave_interval: float = 20.0

@export_group("Архитектор")
## Эссенции за встречу с Архитектором (раз за комнату за забег); шкала — тысячи, числа черновые (game-balance).
@export_range(0, 10000) var architect_essence_reward: int = 150

@export_group("Находки эссенции")
## Источники эссенции в мире; числа черновые. Суммы — НОМИНАЛ: игрок получает его × стат essence_gain (без навыка essence_gain_base).
## Шанс, что на маркере EssenceSpot* лежит находка.
@export_range(0.0, 1.0, 0.01) var essence_find_chance: float = 0.6
## Номинал находки в комнате: от и до, включительно.
@export_range(0, 10000) var essence_find_min: int = 100
@export_range(0, 10000) var essence_find_max: int = 300
## Шанс тайника в КАЖДОМ тупике коридора; выше шанса находки — тупик ещё и крюк.
@export_range(0.0, 1.0, 0.01) var essence_cache_chance: float = 0.75
@export_range(0, 10000) var essence_cache_min: int = 200
@export_range(0, 10000) var essence_cache_max: int = 400
## Доля номинала без навыка «Сбор эссенции» — база стата essence_gain; касание Архитектора её не множит.
@export_range(0.0, 1.0, 0.01) var essence_gain_base: float = 0.3

@export_group("World generation")
## Библиотека пресетов комнат; пусто = все узлы получают placeholder-комнату.
@export var room_preset_library: RS_RoomPresetLibrary
## Ручки генерации (data/world_gen_config.tres): забег берёт СНИМОК (RunManager._run_gen_config), правка — со следующего забега.
@export var world_gen: RS_WorldGenConfig
## Куски коридора (data/corridor_kit.tres).
@export var corridor_kit: RS_CorridorKit
