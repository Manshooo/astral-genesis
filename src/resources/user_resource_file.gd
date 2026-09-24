# res://src/resources/user_resource_file.gd
# Чтение и запись ресурсов-сейвов в user:// — одно правило на всех владельцев
# (WorldSave, SettingsManager, SkillProgression).
#
# Раньше у каждого был свой _load()/_save(), и копии успели разойтись в главном:
# мимо кэша ресурсов (CACHE_MODE_IGNORE) грузил только WorldSave. С кэшем
# повторная загрузка того же пути отдаёт объект, уже лежащий в памяти, а не
# содержимое файла, — то есть «перечитать сейв с диска» молча перечитывает
# память. Сейв — это ровно тот случай, где правда лежит в файле.
class_name UserResourceFile
extends RefCounted


## Ресурс из файла или null: файла нет, он не читается или в нём ресурс чужого
## типа. Два последних случая — повреждённый сейв; о нём предупреждаем, и
## владелец начинает с чистого, а не падает на старте игры.
## [param owner] — кто просит, для текста предупреждения.
static func read(path: String, type: Script, owner: String) -> Resource:
	if not ResourceLoader.exists(path):
		return null
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if loaded == null or not is_instance_of(loaded, type):
		push_warning("%s: файл %s повреждён — начинаю с чистого" % [owner, path])
		return null
	return loaded


## Записать ресурс. false — не вышло, и об этом уже сказано push_error: сейв,
## молча не записанный, игрок обнаружит только при следующей загрузке.
static func write(resource: Resource, path: String, owner: String) -> bool:
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		push_error("%s: не удалось сохранить %s, код ошибки %d" % [owner, path, err])
		return false
	return true
