## GDT_EditorState — чтение/запись project metadata редактора и bind_split (запоминание сплиттеров).
## [[Редакторские инструменты]], раздел «editor_state.gd». Только статика.
@tool
extends RefCounted


## Вне работающего редактора (в т.ч. headless) EditorSettings не инициализирован — отдаём default.
static func read(section: String, key: String, default: Variant) -> Variant:
	if not Engine.is_editor_hint():
		return default
	return EditorInterface.get_editor_settings().get_project_metadata(section, key, default)


## get/set_project_metadata — методы экземпляра синглтона, только через EditorInterface.
static func write(section: String, key: String, value: Variant) -> void:
	if not Engine.is_editor_hint():
		return
	EditorInterface.get_editor_settings().set_project_metadata(section, key, value)


## Ставит на [param split] запомненный offset (или [param default_offset]) и подписывает на dragged;
## вне редактора подписка безвредна.
static func bind_split(
	split: SplitContainer, section: String, key: String, default_offset: int
) -> void:
	split.split_offset = int(read(section, key, default_offset))
	split.dragged.connect(func(offset: int) -> void: write(section, key, offset))
