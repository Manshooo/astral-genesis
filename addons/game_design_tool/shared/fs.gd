## GDT_Fs — файловые мелочи инструментов: slug имени файла, незанятый путь, сохранение нового ресурса, rescan.
## [[Редакторские инструменты]], раздел «shared/». Только статика.
@tool
extends RefCounted


## snake_case из названия. Кириллица сохраняется сознательно — это имя ФАЙЛА; теги нормализует GDT_Tags.tagify.
static func slug(text: String, fallback := "entity") -> String:
	var out := ""
	var prev_us := false
	for c in text.strip_edges().to_lower():
		if _is_word_char(c):
			out += c
			prev_us = false
		elif not prev_us and out != "":
			out += "_"
			prev_us = true
	out = out.rstrip("_")
	return out if out != "" else fallback


## Буква (латиница/кириллица/…) отличается регистром upper≠lower; плюс цифры и «_».
static func _is_word_char(c: String) -> bool:
	return c == "_" or (c >= "0" and c <= "9") or c.to_lower() != c.to_upper()


## Незанятый путь `<dir>/<base>.tres`, при столкновении — `_2`, `_3`, …
static func unique_path(dir: String, base: String, ext := ".tres") -> String:
	ensure_dir(dir)
	var path := "%s/%s%s" % [dir, base, ext]
	var n := 2
	while FileAccess.file_exists(path):
		path = "%s/%s_%d%s" % [dir, base, n, ext]
		n += 1
	return path


static func ensure_dir(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)


## Сохраняет НОВЫЙ ресурс по пути: take_over_path обязателен, иначе ресурс
## останется безымянным в кэше и следующая загрузка по этому пути вернёт не его.
static func save_new(res: Resource, path: String) -> Error:
	res.take_over_path(path)
	var err := ResourceSaver.save(res, path)
	if err == OK:
		rescan()
	return err


## Пересканирование FileSystem редактора: без него созданный файл не появится в
## доке до ручного обновления. get_resource_filesystem() может вернуть null вне
## живого редактора — headless-прогоны инструментов ходят и сюда.
static func rescan() -> void:
	var fs := EditorInterface.get_resource_filesystem()
	if fs != null:
		fs.scan()
