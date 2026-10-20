# res://src/world/scene_loader.gd
## Смена сцены с загрузкой в фоне: ResourceLoader грузит в своём потоке, кадры идут, дерево переключается по готовности. change_scene_to_file грузит синхронно и замораживает кадр (world.tscn ~0.4 с, 0.77 с в редакторе; профайлер 13.10).
## Инстанцирование остаётся на главном потоке (узлы, которые рисуют). Статика, состояния нет.
## Только статика — один вызов на смену сцены, состояния нет.
class_name SceneLoader
extends RefCounted


## Грузит path в фоне и переключает tree; возвращает управление после переключения.
static func change_to(tree: SceneTree, path: String) -> void:
	tree.change_scene_to_packed(await load_scene(tree, path))


## Только загружает path в фоне, отдавая кадры tree, и возвращает сцену — для тех, кому между загрузкой и сменой надо снести свой мир. Не удалась фоновая загрузка — синхронная с ошибкой в лог.
static func load_scene(tree: SceneTree, path: String) -> PackedScene:
	if ResourceLoader.load_threaded_request(path) == OK:
		while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await tree.process_frame
		var scene := ResourceLoader.load_threaded_get(path) as PackedScene
		if scene:
			return scene
	push_error("SceneLoader: «%s» не загрузилась в фоне — гружу синхронно" % path)
	return load(path) as PackedScene
