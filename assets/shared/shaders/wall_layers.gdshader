// Стена без развёртки: координаты берутся из мира, повтор гасится слоями.
//
// У стен кита нет развёртки (UV у них — клетка палитры), и резать их под
// текстуру не нужно. Проекция по мировым координатам даёт одни и те же 256 px/м
// на любой детали любого стиля, и одна деталь принимает любой набор текстур:
// вид стены решает материал, а не меш. Стены кита вертикальны, поэтому плоскость
// проекции одна на грань (по нормали), без смешивания трёх, как у triplanar.
// Горизонтальные грани (верх карниза, низ балки) проецируются сверху.
//
// Слои:
// 1. База — бетон без линий, гекс-тайлинг (Mikkelsen 2022, «Practical Real-Time
//    Hex-Tiling», по Heitz–Neyret 2018). Три выборки со случайным сдвигом с
//    вершин треугольной сетки, смешанные с весом от яркости. Стык гексов
//    прячется в органике, а прямая линия на нём раздвоилась бы, поэтому в базе
//    линий нет. Поворот по умолчанию выключен: потёки на стене вертикальны.
// 2. Опалубка — шов и стяжки одной панели строго по сетке. Регулярный рисунок
//    повторяется и в жизни, и глаз его принимает. Сетка привязана к миру: центры
//    клеток лежат в кратных 8 м (SquareGridEmbedding.cell_origin), и при ширине
//    панели, делящей 4 м, шов лёг бы на край клетки. Но стена стоит толщиной
//    внутрь клетки, и шов на краю ушёл бы в толщу соседней стены: внутренний угол
//    комнаты остался бы без шва. Поэтому сетка сдвинута на толщину стены — шов
//    ложится в левый конец каждой грани, то есть в каждый внутренний угол
//    (у одной из двух стен угла). Каждая панель получает свой тон, как
//    отдельная заливка.
// 3. Макро-пятна — шум крупнее текстуры: на 8-метровой стене не читается
//    квадрат 4 м.
// 4. Низ темнее (Визуальный стиль §2.1): объём без запекания.
// Уникальное — трещины, сколы, потёки — идёт декалями, не в текстуру: всё
// приметное в тайлящейся карте и есть видимый повтор.
//
// Цена: 3 × 3 выборки базы и 2 выборки панели. Для стен это ничто (§2.2).
shader_type spatial;

group_uniforms base;
uniform sampler2D base_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_roughness : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
// Метров на одну текстуру базы: 1024² на 4 м — 256 px/м.
uniform float base_tex_m = 4.0;
// Выключатель гексов — для сравнения с простым повтором и замера цены.
uniform bool hex_tiling = true;
// Шаг треугольной сетки. Мельче — повтор пропадает раньше, но и пятна базы
// режутся на куски мельче.
uniform float hex_size_m = 2.0;
// Доля полного оборота, на которую может повернуться гекс.
uniform float hex_rotation : hint_range(0.0, 1.0) = 0.0;
// Резкость стыка гексов: выше — меньше зона смешивания и меньше «мыла».
uniform float hex_contrast : hint_range(0.01, 0.99) = 0.65;
// Насколько светлое пятно перекрывает тёмное на стыке: без этого стык — ровный
// полупрозрачный переход, по которому сетка гексов и читается.
uniform float hex_luma_weight : hint_range(0.0, 1.0) = 0.6;

group_uniforms panel;
// Множитель цвета панели: белое не меняет базу, шов и стяжки тёмные.
uniform sampler2D panel_ao : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D panel_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// Ширина × высота панели. Ширина делит 4 м, высота — высоту стены.
uniform vec2 panel_size_m = vec2(1.0, 2.0);
// Сдвиг сетки: по ширине — толщина стены кита (Метрики и кит §2), по высоте —
// от пола уровня. Стена станет тоньше — сдвиг меняется вместе с ней.
uniform vec2 panel_offset_m = vec2(0.25, 0.0);
// Разброс тона между панелями.
uniform float panel_tone : hint_range(0.0, 0.3) = 0.05;
// Насколько шов шершавее плоскости панели.
uniform float panel_seam_roughness : hint_range(0.0, 1.0) = 0.3;

group_uniforms macro;
uniform float macro_size_m = 7.0;
uniform float macro_albedo : hint_range(0.0, 0.5) = 0.12;
uniform float macro_roughness : hint_range(0.0, 0.5) = 0.08;

group_uniforms grime;
uniform float grime_height_m = 1.5;
uniform float grime_strength : hint_range(0.0, 1.0) = 0.25;
// Высота уровня: низ темнеет от пола каждого уровня многоуровневой детали.
uniform float level_height_m = 8.0;

group_uniforms;
uniform float normal_depth : hint_range(0.0, 4.0) = 1.0;

varying vec3 world_pos;
varying vec3 world_normal;

const vec3 LUMA = vec3(0.299, 0.587, 0.114);

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = MODEL_NORMAL_MATRIX * NORMAL;
}

// Hash without Sine, Dave Hoskins (MIT): без sin, который на разных GPU даёт
// разные младшие биты.
vec2 hash22(vec2 p) {
	vec3 p3 = fract(p.xyx * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p, float seed) {
	vec2 i = floor(p);
	vec2 f = p - i;
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash13(vec3(i, seed));
	float b = hash13(vec3(i + vec2(1.0, 0.0), seed));
	float c = hash13(vec3(i + vec2(0.0, 1.0), seed));
	float d = hash13(vec3(i + vec2(1.0, 1.0), seed));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

mat2 rotation(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

// Треугольная сетка Heitz–Neyret в безветвевой записи Mikkelsen: три вершины
// треугольника вокруг точки и барицентрические веса.
void triangle_grid(vec2 g, out vec3 w, out vec2 v1, out vec2 v2, out vec2 v3) {
	vec2 skew = vec2(g.x, -0.57735027 * g.x + 1.15470054 * g.y);
	vec2 base = floor(skew);
	vec3 t = vec3(fract(skew), 0.0);
	t.z = 1.0 - t.x - t.y;
	float s = step(0.0, -t.z);
	float s2 = 2.0 * s - 1.0;
	w = vec3(-t.z * s2, s - t.y * s2, s - t.x * s2);
	v1 = base + vec2(s, s);
	v2 = base + vec2(s, 1.0 - s);
	v3 = base + vec2(1.0 - s, s);
}

// Gain Перлина, нормированный на сумму: стягивает веса к 0 и 1.
vec3 gain3(vec3 x, float r) {
	float k = log(1.0 - r) / log(0.5);
	vec3 s = 2.0 * step(0.5, x);
	vec3 m = 2.0 * (1.0 - s);
	vec3 res = 0.5 * s + 0.25 * m * pow(max(vec3(0.0), s + x * m), vec3(k));
	return res / (res.x + res.y + res.z);
}

// Плоскость проекции q — метры, x вправо, y вверх, если смотреть на грань. Картинка
// кладётся верхом вверх, и зелёный канал нормали (OpenGL, вверх по картинке)
// совпадает с q.y — знаки ни на одной грани не путаются.
struct BaseSample {
	vec3 albedo;
	vec2 normal;	// xy нормали в осях q
	float roughness;
};

BaseSample sample_base(vec2 q, vec2 dqx, vec2 dqy, vec2 vertex) {
	vec2 h = hash22(vertex + 0.5);
	float angle = (hash13(vec3(vertex, 3.0)) * 2.0 - 1.0) * PI * hex_rotation;
	mat2 r = rotation(angle);
	// Центр вершины в метрах — обратная косая матрица сетки.
	vec2 center = vec2(vertex.x, 0.5 * vertex.x + 0.8660254 * vertex.y) * hex_size_m;
	vec2 qr = r * (q - center) + center + h * base_tex_m;
	// Производные — от сплошной q, повёрнутые той же матрицей: у qr на стыке
	// треугольников скачок, и мипмап по нему выбрал бы самый мелкий уровень.
	vec2 dx = r * dqx;
	vec2 dy = r * dqy;
	vec2 uv = vec2(qr.x, -qr.y) / base_tex_m;
	vec2 duvx = vec2(dx.x, -dx.y) / base_tex_m;
	vec2 duvy = vec2(dy.x, -dy.y) / base_tex_m;
	BaseSample o;
	o.albedo = textureGrad(base_albedo, uv, duvx, duvy).rgb;
	o.roughness = textureGrad(base_roughness, uv, duvx, duvy).r;
	// Нормаль гекса — в повёрнутых осях; в оси q её возвращает R^T.
	o.normal = transpose(r) * (textureGrad(base_normal, uv, duvx, duvy).xy * 2.0 - 1.0);
	return o;
}

vec3 unpack_z(vec2 xy) {
	// Карты нормалей сжаты в два канала (RGTC), z восстанавливается из xy.
	return vec3(xy, sqrt(max(0.0, 1.0 - dot(xy, xy))));
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec3 right = abs(n.y) > 0.7 ? vec3(1.0, 0.0, 0.0) : normalize(vec3(n.z, 0.0, -n.x));
	vec3 up = normalize(cross(n, right));
	vec2 q = vec2(dot(world_pos, right), dot(world_pos, up));
	vec2 dqx = dFdx(q);
	vec2 dqy = dFdy(q);
	// Номер плоскости грани: параллельные стены с одинаковым q получают разный
	// разброс панелей и пятен.
	float plane = floor(dot(world_pos, n) * 4.0 + 0.5);

	BaseSample b;
	if (hex_tiling) {
		vec3 w;
		vec2 v1, v2, v3;
		triangle_grid(q / hex_size_m, w, v1, v2, v3);
		BaseSample s1 = sample_base(q, dqx, dqy, v1);
		BaseSample s2 = sample_base(q, dqx, dqy, v2);
		BaseSample s3 = sample_base(q, dqx, dqy, v3);
		vec3 lum = vec3(dot(s1.albedo, LUMA), dot(s2.albedo, LUMA), dot(s3.albedo, LUMA));
		lum = mix(vec3(1.0), lum, hex_luma_weight);
		vec3 k = lum * pow(w, vec3(7.0));
		k /= k.x + k.y + k.z;
		k = gain3(k, hex_contrast);
		b.albedo = k.x * s1.albedo + k.y * s2.albedo + k.z * s3.albedo;
		b.normal = k.x * s1.normal + k.y * s2.normal + k.z * s3.normal;
		b.roughness = k.x * s1.roughness + k.y * s2.roughness + k.z * s3.roughness;
	} else {
		vec2 uv = vec2(q.x, -q.y) / base_tex_m;
		vec2 duvx = vec2(dqx.x, -dqx.y) / base_tex_m;
		vec2 duvy = vec2(dqy.x, -dqy.y) / base_tex_m;
		b.albedo = textureGrad(base_albedo, uv, duvx, duvy).rgb;
		b.roughness = textureGrad(base_roughness, uv, duvx, duvy).r;
		b.normal = textureGrad(base_normal, uv, duvx, duvy).xy * 2.0 - 1.0;
	}

	vec2 pq = (q - panel_offset_m) / panel_size_m;
	vec2 cell = floor(pq);
	vec2 puv = vec2(pq.x - cell.x, 1.0 - (pq.y - cell.y));
	vec2 dpx = vec2(dqx.x, -dqx.y) / panel_size_m;
	vec2 dpy = vec2(dqy.x, -dqy.y) / panel_size_m;
	float ao = textureGrad(panel_ao, puv, dpx, dpy).r;
	vec2 pn = textureGrad(panel_normal, puv, dpx, dpy).xy * 2.0 - 1.0;
	float tone = 1.0 + (hash13(vec3(cell, plane)) - 0.5) * 2.0 * panel_tone;

	vec2 mq = (q + plane * vec2(0.37, 0.61)) / macro_size_m;
	float macro = 0.65 * value_noise(mq, 11.0) + 0.35 * value_noise(mq * 2.3, 17.0);

	float h = mod(world_pos.y - NODE_POSITION_WORLD.y, level_height_m);
	float grime = 1.0 - smoothstep(0.0, grime_height_m, h);

	vec3 albedo = b.albedo * ao * tone;
	albedo *= 1.0 + (macro - 0.5) * 2.0 * macro_albedo;
	albedo *= 1.0 - grime_strength * grime;
	ALBEDO = albedo;
	float rough = b.roughness + (0.5 - macro) * 2.0 * macro_roughness;
	ROUGHNESS = clamp(mix(rough, 1.0, (1.0 - ao) * panel_seam_roughness), 0.0, 1.0);
	METALLIC = 0.0;

	// Нормаль собирается в мире сама: касательные меша построены по развёртке
	// палитры, где у всей грани одна точка UV, и NORMAL_MAP по ним не годится.
	// База и шов складываются по whiteout.
	vec3 bn = unpack_z(b.normal);
	vec3 sn = unpack_z(pn);
	vec3 t = normalize(vec3((bn.xy + sn.xy) * normal_depth, bn.z * sn.z));
	vec3 nw = normalize(right * t.x + up * t.y + n * t.z);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
}
