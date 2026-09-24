// Обводка силуэтом по экранной маске.
//
// Вход — маска выделенного объекта (SubViewport, где рендерится только слой
// обводки): альфа 1 там, где объект, 0 везде. Контур считается ПО МАСКЕ, а не по
// геометрии, и отсюда всё, ради чего затевался постэффект: толщина задана в
// пикселях и не зависит ни от размера объекта, ни от расстояния до него, а
// составной объект (рама + полотно + ручка) даёт один силуэт без внутренних
// рёбер — маска не знает, из скольких мешей он собран.
//
// Маску читаем по SCREEN_UV, а не по UV: прямоугольник, на котором мы рисуем,
// обрезан по экранным габаритам объекта (S_OutlineMask), и его собственный UV
// ничего не говорит о положении на экране.
shader_type canvas_item;
render_mode unshaded;

// Потолок радиуса поиска. Константа, а не uniform: границы цикла в шейдере
// обязаны быть известны на компиляции, а число выборок здесь квадратично —
// (2*MAX+1)^2. Реальная толщина берётся из thickness и ограничена этим потолком.
const int MAX_RADIUS = 4;

uniform sampler2D mask_tex : filter_nearest, repeat_disable;
uniform vec4 outline_color : source_color = vec4(0.227, 0.361, 0.714, 1.0);
uniform float thickness : hint_range(1.0, 4.0, 0.5) = 2.0;

void fragment() {
	vec2 texel = 1.0 / vec2(textureSize(mask_tex, 0));

	// Внутри силуэта не рисуем: контур идёт СНАРУЖИ. Иначе он съедал бы сам
	// объект — и тем сильнее, чем мельче объект на экране.
	if (texture(mask_tex, SCREEN_UV).a > 0.5) {
		discard;
	}

	// Расстояние (в текселях) до ближайшего закрашенного пикселя маски.
	float limit = thickness + 0.5;
	float nearest = limit + 1.0;
	for (int x = -MAX_RADIUS; x <= MAX_RADIUS; x++) {
		for (int y = -MAX_RADIUS; y <= MAX_RADIUS; y++) {
			vec2 offset = vec2(float(x), float(y));
			float distance_px = length(offset);
			// Круглое ядро вместо квадратного: с квадратным толщина обводки по
			// диагонали была бы в 1.4 раза больше, чем по вертикали.
			// distance_px >= nearest — выборка уже не может улучшить результат.
			if (distance_px > limit || distance_px >= nearest) {
				continue;
			}
			if (texture(mask_tex, SCREEN_UV + offset * texel).a > 0.5) {
				nearest = distance_px;
			}
		}
	}

	// Мягкий внешний край шириной в тексель: маска рендерится без сглаживания
	// (MSAA на ней выключен ради цены), и без этого силуэт был бы «лесенкой».
	float edge = smoothstep(limit, thickness - 0.5, nearest);
	if (edge <= 0.0) {
		discard;
	}
	COLOR = vec4(outline_color.rgb, outline_color.a * edge);
}
