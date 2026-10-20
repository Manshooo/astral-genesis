## Свет комплекса по слоям (data/depth_lighting.tres): элемент на слой, а не кривая — «что на хабе» читается одной строкой.
## Элементов может быть больше слоёв генератора. Читают LevelEnvironment, LevelLight, LayerStreamer, экран калибровки.
class_name RS_DepthLighting
extends Resource

const PATH := "res://data/depth_lighting.tres"

## Индекс — глубина: 0 — поверхность (RS_LevelGraph.DEPTHS).
@export var layers: Array[RS_DepthLight] = []


## Свет слоя depth; глубже последнего — последний.
func for_depth(depth: int) -> RS_DepthLight:
	if layers.is_empty():
		return null
	return layers[clampi(depth, 0, layers.size() - 1)]


## Ресурс, загруженный при первом layer(): load() из кэша стоил ~0.7 мс, а ламп 150–270 за вход (профайлер 13.10). Тот же экземпляр — правка .tres видна.
static var _loaded: RS_DepthLighting


## Свет слоя из data/depth_lighting.tres; null — файла или слоёв нет.
static func layer(depth: int) -> RS_DepthLight:
	if _loaded == null:
		_loaded = load(PATH) as RS_DepthLighting
	return _loaded.for_depth(depth) if _loaded else null
