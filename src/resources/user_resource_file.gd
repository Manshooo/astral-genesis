# res://src/resources/user_resource_file.gd
# Чтение и запись ресурсов-сейвов в user:// — одно правило на всех (WorldSave, SettingsManager, SkillProgression).
# Читаем мимо кэша ресурсов (CACHE_MODE_IGNORE): иначе «перечитать с диска» отдаёт объект из памяти.
class_name UserResourceFile
extends RefCounted


## Ресурс из файла или null (нет, не читается или чужого типа); повреждённый — предупреждение, владелец начинает с чистого. [param owner] — для текста.
static func read(path: String, type: Script, owner: String) -> Resource:
	if not ResourceLoader.exists(path):
		return null
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if loaded == null or not is_instance_of(loaded, type):
		push_warning("%s: файл %s повреждён — начинаю с чистого" % [owner, path])
		return null
	return loaded


## Записать ресурс; false — не вышло, push_error уже сказал.
static func write(resource: Resource, path: String, owner: String) -> bool:
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		push_error("%s: не удалось сохранить %s, код ошибки %d" % [owner, path, err])
		return false
	return true
