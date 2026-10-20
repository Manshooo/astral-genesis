## GDT_Undo — правка ресурсов инструментов через историю редактора: Ctrl+Z откатывает и значение, и файл.
## [[Редакторские инструменты]], раздел «История правок». Вне редактора правка применяется и сохраняется напрямую.
@tool
extends RefCounted

## Одна правка: [param target] — чей это ресурс, [param changes] — {свойство:
## [было, стало]}, [param save_as] — какой файл переписать (null — сам target).
class Edit:
	extends RefCounted

	var target: Object
	var changes: Dictionary
	var save_as: Resource

	func _init(p_target: Object, p_changes: Dictionary, p_save_as: Resource = null) -> void:
		target = p_target
		changes = p_changes
		save_as = p_save_as if p_save_as != null else p_target as Resource


## Исполнитель шагов истории: EditorUndoRedoManager зовёт методы объектов, а не
## Callable, поэтому сохранение и «перерисуй» живут на одном общем экземпляре.
class _Runner:
	extends RefCounted

	var last_error := OK

	func save_all(resources: Array) -> void:
		last_error = OK
		for res: Resource in resources:
			if res == null or res.resource_path == "":
				continue
			var err := ResourceSaver.save(res, res.resource_path)
			if err != OK:
				last_error = err
				push_error("GDT_Undo: не удалось сохранить %s (код %d)" % [res.resource_path, err])

	func run(callback: Callable) -> void:
		if callback.is_valid():
			callback.call()


static var _runner := _Runner.new()


## Правка одного ресурса. Возвращает код сохранения — строку статуса показывает
## вызывающий, у каждого инструмента она своя.
## [param merge] — склеивать подряд идущие одноимённые действия в одно (тики
## спинбокса при перетаскивании), иначе история заполняется сотней шагов.
static func commit(
	action: String,
	target: Resource,
	changes: Dictionary,
	on_applied := Callable(),
	merge := false,
) -> Error:
	return commit_many(action, [Edit.new(target, changes)], on_applied, merge)


## Правка нескольких ресурсов одним шагом истории (переименование тега по всем
## пресетам и словарю): откатывается всё вместе, а не по файлу.
static func commit_many(
	action: String, edits: Array, on_applied := Callable(), merge := false
) -> Error:
	var to_save := _files_of(edits)
	var history := _history()
	if history == null:
		for edit: Edit in edits:
			for property: String in edit.changes:
				edit.target.set(property, _copy(edit.changes[property][1]))
		_runner.save_all(to_save)
		_runner.run(on_applied)
		return _runner.last_error

	history.create_action(action, UndoRedo.MERGE_ENDS if merge else UndoRedo.MERGE_DISABLE)
	for edit: Edit in edits:
		for property: String in edit.changes:
			history.add_do_property(edit.target, property, _copy(edit.changes[property][1]))
			history.add_undo_property(edit.target, property, _copy(edit.changes[property][0]))
	# Сохранение и перерисовка — ПОСЛЕ свойств и в do, и в undo: undo-шаги идут в
	# порядке добавления, так что файл пишется уже с откаченным значением.
	history.add_do_method(_runner, &"save_all", to_save)
	history.add_undo_method(_runner, &"save_all", to_save)
	history.add_do_method(_runner, &"run", on_applied)
	history.add_undo_method(_runner, &"run", on_applied)
	history.commit_action()
	return _runner.last_error


## Массив «было/стало» копируем: иначе история держала бы ТОТ ЖЕ массив, что и
## ресурс, и следующая правка на месте переписала бы и прошлое.
static func _copy(value: Variant) -> Variant:
	if value is Array or value is Dictionary:
		return value.duplicate()
	return value


static func _files_of(edits: Array) -> Array:
	var out: Array = []
	for edit: Edit in edits:
		if edit.save_as != null and not out.has(edit.save_as):
			out.append(edit.save_as)
	return out


static func _history() -> EditorUndoRedoManager:
	if not Engine.is_editor_hint():
		return null
	return EditorInterface.get_editor_undo_redo()
