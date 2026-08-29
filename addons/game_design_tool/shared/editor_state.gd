## res://addons/game_design_tool/shared/editor_state.gd
## GDT_EditorState — чтение/запись project metadata редактора: тот же приём,
## которым world_gen.gd уже помнил сид/глубину/оверлеи/камеру между запусками
## редактора, раньше лежал копией (_get_meta/_set_meta) в нём и в presets.gd.
## Третья копия понадобилась main_screen.gd (какая вкладка была открыта) —
## тот порог, после которого «пять строк на два файла» стало «один и тот же
## инвариант в трёх местах», а не поводом для новой абстракции ради неё самой.
##
## Здесь же bind_split: сплиттеры, подвинутые рукой (список пресетов ↔
## карточка, вьюпорт ↔ боковая панель и т.д.), раньше сбрасывались на
## захардкоженный дефолт при каждом перезапуске редактора — теперь то же
## хранилище, что и у остальных настроек вкладки.
##
## Только статика — состояния нет, как и у соседних shared/-модулей.
@tool
extends RefCounted


## EditorSettings — редакторский API: вне настоящего работающего редактора (в
## т.ч. в headless-прогонах сцен, где Engine.is_editor_hint() ложно) singleton
## не инициализирован, а состояние заведомо некому читать между сессиями
## редактора, которых не было.
static func read(section: String, key: String, default: Variant) -> Variant:
	if not Engine.is_editor_hint():
		return default
	return EditorInterface.get_editor_settings().get_project_metadata(section, key, default)


## set_project_metadata/get_project_metadata — методы ЭКЗЕМПЛЯРА синглтона (не
## статика класса EditorSettings) — только через EditorInterface.
static func write(section: String, key: String, value: Variant) -> void:
	if not Engine.is_editor_hint():
		return
	EditorInterface.get_editor_settings().set_project_metadata(section, key, value)


## Ставит на [param split] запомненное соотношение (или [param default_offset],
## если ещё не запоминали) и подписывает на dragged — подвинуть рукой нужно
## один раз, а не при каждом запуске редактора. Вне редактора dragged всё равно
## не придёт, а write() внутри нет-опнется сама, так что подписка безвредна и
## в headless-прогонах.
static func bind_split(
	split: SplitContainer, section: String, key: String, default_offset: int
) -> void:
	split.split_offset = int(read(section, key, default_offset))
	split.dragged.connect(func(offset: int) -> void: write(section, key, offset))
