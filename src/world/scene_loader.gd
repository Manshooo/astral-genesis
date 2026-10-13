# res://src/world/scene_loader.gd
## Смена сцены с загрузкой в фоне: ResourceLoader грузит сцену в своём потоке,
## кадры тем временем идут, и дерево переключается, когда она готова.
##
## Зачем: change_scene_to_file грузит сцену синхронно, и кадр нажатия замирает.
## Для world.tscn это ~0.4 с без редактора и ~0.77 с в нём (профайлер 13.10,
## _on_new_game_pressed); инстанцирование при этом — около миллисекунды, так что
## почти весь фриз — именно загрузка, и её можно унести с главного потока.
## Инстанцирование остаётся на нём: в сцене узлы, которые рисуют, а их не
## создают из других потоков.
##
## Только статика — один вызов на смену сцены, состояния нет.
class_name SceneLoader
extends RefCounted


## Грузит [param path] в фоне и переключает на неё [param tree]. Возвращает
## управление после переключения.
static func change_to(tree: SceneTree, path: String) -> void:
	tree.change_scene_to_packed(await load_scene(tree, path))


## Только загружает [param path] в фоне, отдавая кадры [param tree], и
## возвращает сцену — для тех, кому между загрузкой и сменой надо ещё снести
## свой мир: снеси его до загрузки, и все эти кадры игрок смотрел бы в пустоту.
## Не удалась фоновая загрузка — синхронная, как раньше, с ошибкой в лог: фриз
## лучше застрявшей смены сцены.
static func load_scene(tree: SceneTree, path: String) -> PackedScene:
	if ResourceLoader.load_threaded_request(path) == OK:
		while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await tree.process_frame
		var scene := ResourceLoader.load_threaded_get(path) as PackedScene
		if scene:
			return scene
	push_error("SceneLoader: «%s» не загрузилась в фоне — гружу синхронно" % path)
	return load(path) as PackedScene
