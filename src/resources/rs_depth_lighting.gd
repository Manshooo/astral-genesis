## Свет комплекса по слоям — data/depth_lighting.tres. Слоем на элемент, а не
## кривой от глубины: слоёв пять, переход между ними — смена слоя целиком
## (портал), плавности между ними не видно, а «что стоит на хабе» должно читаться
## в инспекторе одной строкой, а не вычисляться из формы кривой.
##
## Кто читает: LevelEnvironment (фоновый свет, туман), LevelLight (энергия ламп),
## LayerStreamer (погасшие лампы коридора).
class_name RS_DepthLighting
extends Resource

const PATH := "res://data/depth_lighting.tres"

## Индекс — глубина: 0 — поверхность, дальше вглубь (RS_LevelGraph.DEPTHS).
@export var layers: Array[RS_DepthLight] = []


## Свет слоя [param depth]. Глубже последнего элемента — последний: новый слой
## на дне не должен остаться без света до того, как его допишут сюда.
func for_depth(depth: int) -> RS_DepthLight:
	if layers.is_empty():
		return null
	return layers[clampi(depth, 0, layers.size() - 1)]


## Ресурс, загруженный при первом вызове layer(). Каждая лампа слоя спрашивает свой
## свет при спавне и на каждой смене слоя — 150–270 вызовов за вход в забег, — а
## load() даже из кэша ресурсов стоил ~0.7 мс (профайлер, 13.10: 106 мс на 154
## вызова). Держим ссылку здесь: тот же экземпляр, что вернул бы load(), так что
## правка .tres в инспекторе во время игры видна по-прежнему.
static var _loaded: RS_DepthLighting


## Свет слоя из data/depth_lighting.tres; null — файла нет или слоёв в нём нет.
static func layer(depth: int) -> RS_DepthLight:
	if _loaded == null:
		_loaded = load(PATH) as RS_DepthLighting
	return _loaded.for_depth(depth) if _loaded else null
