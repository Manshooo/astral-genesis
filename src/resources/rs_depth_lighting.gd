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


## Свет слоя из data/depth_lighting.tres; null — файла нет или слоёв в нём нет.
static func layer(depth: int) -> RS_DepthLight:
	var lighting := load(PATH) as RS_DepthLighting
	return lighting.for_depth(depth) if lighting else null
