extends RefCounted
## Источники клипов полигона: основные библиотеки ригов и их версии из dev/polygon/clips/ — выгрузку из Blender кладут
## туда и сравнивают с основной, не трогая assets/. Выбранная версия подменяет основную во всех деревьях полигона:
## у манекена, у трупа и у надетого игроком облика. Вики: [[Полигон]].

## Куда класть версию клипов. Папка в .gitignore: версия — черновик для сравнения, в git ей не место.
const VARIANTS_DIR := "res://dev/polygon/clips/"
## Где лежат основные библиотеки клипов — по одной на тип рига.
const RIGS_DIR := "res://assets/characters/_rigs/"
## Выбор версии или перечитанные файлы: стенд клипов ведёт свои библиотеки сам и пересобирает их по этому сигналу.
signal changed

## Метка подменённой библиотеки: путь основной, вместо которой она стоит.
const META_OFFICIAL := &"polygon_official"
## Метка подменённой библиотеки: клипы, которые взяты из версии, а не из основной.
const META_OVERRIDDEN := &"polygon_overridden"
## Узел-микшер с этой меткой выбирает клипы сам (стенд клипов) — общая подмена его не трогает.
const META_OWN_CLIPS := &"polygon_own_clips"

## Основные библиотеки по пути файла.
var officials: Dictionary[String, AnimationLibrary] = {}
## Версии: { "path", "title", "official" (путь основной), "library" }.
var variants: Array[Dictionary] = []
## Путь основной → путь выбранной версии; нет ключа — основная.
var chosen: Dictionary[String, String] = {}

var _merged: Dictionary[String, AnimationLibrary] = {}
var _tree: SceneTree


func _init() -> void:
	reload()


## Перечитывает основные библиотеки и папку версий. [param from_disk] — мимо кэша ресурсов: файл, перевыгруженный из
## Blender и переимпортированный редактором, пока игра идёт, иначе остался бы прежним. Версия, у которой не нашлось
## основной, пропускается с предупреждением: молча проигнорированный файл выглядел бы как «версия не работает».
func reload(from_disk := false) -> void:
	var mode := ResourceLoader.CACHE_MODE_REPLACE if from_disk else ResourceLoader.CACHE_MODE_REUSE
	officials.clear()
	variants.clear()
	_merged.clear()
	for path in _files_under(RIGS_DIR):
		var library := ResourceLoader.load(path, "", mode) as AnimationLibrary
		if library != null:
			officials[path] = library
	for path in _files_under(VARIANTS_DIR):
		var library := load_library(path, mode)
		if library == null:
			continue
		var official := official_for_file(path.get_file(), officials.keys())
		if official == "":
			push_warning("Полигон: версия «%s» не подходит ни к одной библиотеке %s — имя файла должно начинаться с имени основной"
				% [path.get_file(), RIGS_DIR])
			continue
		variants.append({"path": path, "title": path.get_file().get_basename(), "official": official, "library": library})
	for official in chosen.keys():
		if not variants.any(func(v: Dictionary) -> bool: return v.path == chosen[official]):
			chosen.erase(official)


## Библиотека из файла: импортированная как AnimationLibrary — как есть; как сцена (импорт .glb по умолчанию) — клипы
## всех её AnimationPlayer одной библиотекой. Так версию не надо переключать на импорт «Animation Library» руками.
static func load_library(path: String, mode := ResourceLoader.CACHE_MODE_REUSE) -> AnimationLibrary:
	var resource := ResourceLoader.load(path, "", mode)
	if resource is AnimationLibrary:
		return resource
	if not resource is PackedScene:
		return null
	var probe := (resource as PackedScene).instantiate()
	var library := AnimationLibrary.new()
	for mixer: AnimationMixer in probe.find_children("*", "AnimationMixer", true, false):
		for key in mixer.get_animation_library_list():
			var source := mixer.get_animation_library(key)
			for clip in source.get_animation_list():
				library.add_animation(clip, source.get_animation(clip))
	probe.free()
	return library if not library.get_animation_list().is_empty() else null


## К какой основной относится версия: имя её файла начинается с имени основной, выигрывает самое длинное —
## «ANIM_quadruped_tail_взмах.glb» относится к «ANIM_quadruped_tail», а не к «ANIM_quadruped». "" — ни к какой.
static func official_for_file(file_name: String, official_paths: Array) -> String:
	var best := ""
	for path: String in official_paths:
		var stem := path.get_file().get_basename()
		if file_name.begins_with(stem) and stem.length() > best.get_file().get_basename().length():
			best = path
	return best


func variants_of(official_path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for variant in variants:
		if variant.official == official_path:
			out.append(variant)
	return out


## Основная библиотека, клипы которой поверх неё заменены клипами версии с теми же именами; клипы, которых в версии
## нет, остаются основными — версия может нести один клип.
func merged(official_path: String, variant_path: String) -> AnimationLibrary:
	if _merged.has(variant_path):
		return _merged[variant_path]
	var official := officials[official_path]
	var variant: AnimationLibrary = null
	for candidate in variants:
		if candidate.path == variant_path:
			variant = candidate.library
	var library := AnimationLibrary.new()
	var overridden := PackedStringArray()
	for clip in official.get_animation_list():
		if variant != null and variant.has_animation(clip):
			library.add_animation(clip, variant.get_animation(clip))
			overridden.append(clip)
		else:
			library.add_animation(clip, official.get_animation(clip))
	# Клипы, которых в основной нет, — тоже: новый клип смотрят на стенде раньше, чем он попал в дерево.
	if variant != null:
		for clip in variant.get_animation_list():
			if not library.has_animation(clip):
				library.add_animation(clip, variant.get_animation(clip))
				overridden.append(clip)
	library.set_meta(META_OFFICIAL, official_path)
	library.set_meta(META_OVERRIDDEN, overridden)
	_merged[variant_path] = library
	return library


## Путь основной библиотеки, которую представляет [param library] (сама основная или подменённая), или "".
func official_path_of(library: AnimationLibrary) -> String:
	if library == null:
		return ""
	if library.has_meta(META_OFFICIAL):
		return library.get_meta(META_OFFICIAL)
	for path in officials:
		if officials[path] == library:
			return path
	# Перечитанная с диска основная могла встать в кэш новым объектом — старый узнаётся по пути.
	return library.resource_path if officials.has(library.resource_path) else ""


## Что сейчас должно стоять вместо основной [param official_path]: выбранная версия или она сама.
func current(official_path: String) -> AnimationLibrary:
	if chosen.has(official_path):
		return merged(official_path, chosen[official_path])
	return officials[official_path]


## Выбрать версию для основной ("" — вернуть основную) и подменить её во всех деревьях сцены.
func choose(official_path: String, variant_path: String) -> void:
	if variant_path == "":
		chosen.erase(official_path)
	else:
		chosen[official_path] = variant_path
	sweep()


## Ставит выбранное во все микшеры сцены. Кэш микшера сбрасывается: после чтения с диска библиотека та же, а клипы в
## ней новые.
func sweep() -> void:
	if _tree != null:
		for mixer: AnimationMixer in _tree.root.find_children("*", "AnimationMixer", true, false):
			apply(mixer)
			mixer.clear_caches()
	changed.emit()


## Ставит в микшер то, что выбрано для каждой его основной библиотеки.
func apply(mixer: AnimationMixer) -> void:
	if not is_instance_valid(mixer) or mixer.get_meta(META_OWN_CLIPS, false):
		return
	for key in mixer.get_animation_library_list():
		var library := mixer.get_animation_library(key)
		var official := official_path_of(library)
		if official == "" or not officials.has(official):
			continue
		var wanted := current(official)
		if wanted != library:
			mixer.remove_animation_library(key)
			mixer.add_animation_library(key, wanted)


## Следить за деревом: новые микшеры (манекен, труп) и смена библиотек у старых (облик надели) получают
## выбранную версию. Отложенно — библиотеки меняет O_BodyVisual посреди своего цикла.
func watch(tree: SceneTree) -> void:
	_tree = tree
	tree.node_added.connect(_on_node_added)
	for mixer: AnimationMixer in tree.root.find_children("*", "AnimationMixer", true, false):
		_track(mixer)


func unwatch() -> void:
	if _tree != null and _tree.node_added.is_connected(_on_node_added):
		_tree.node_added.disconnect(_on_node_added)
	_tree = null


func _on_node_added(node: Node) -> void:
	if node is AnimationMixer:
		_track(node as AnimationMixer)


func _track(mixer: AnimationMixer) -> void:
	if not mixer.animation_libraries_updated.is_connected(_on_libraries_updated):
		mixer.animation_libraries_updated.connect(_on_libraries_updated.bind(mixer))
	apply.call_deferred(mixer)


func _on_libraries_updated(mixer: AnimationMixer) -> void:
	apply.call_deferred(mixer)


## Файлы ресурсов под папкой, рекурсивно; .import и .uid — не ресурсы.
static func _files_under(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir_path):
		return out
	for file in DirAccess.get_files_at(dir_path):
		var path := dir_path.path_join(file)
		if file.get_extension() in ["import", "uid", "gitignore", "md"] or not ResourceLoader.exists(path):
			continue
		out.append(path)
	for sub in DirAccess.get_directories_at(dir_path):
		out.append_array(_files_under(dir_path.path_join(sub)))
	return out
