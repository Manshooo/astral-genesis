// Тайлинговая текстура плит без видимого повтора: каждая плита берёт случайную
// плиту текстуры в одной из 8 ориентаций (4 поворота × зеркало).
//
// Текстура — сетка slabs × slabs плит со швами-бороздками по краям сетки. Шов
// между соседними плитами ложится в бороздку, поэтому соседей не смешиваем
// (как у Квилеса или в hex-tiling) и выборка на карту одна. Смешивание здесь
// только навредило бы: бороздки раздвоились бы. Для органики без сетки (грязь,
// гранж) нужен hex-tiling, а не этот шейдер.
//
// Развёртка в метрах — из Blender (tools/kit_materials.py арт-репозитория,
// 1 текстура = 4 м, 256 px/м). Материал там простой, без перемешивания: в
// превью Blender видна обычная плитка с периодом 4 м, а повтор гасится здесь.
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform int slabs = 4;
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
uniform float normal_depth : hint_range(0.0, 4.0) = 1.0;

// Hash without Sine, Dave Hoskins (MIT): без sin, который на разных GPU даёт
// разные младшие биты.
vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

void fragment() {
	float n = float(slabs);
	vec2 p = UV * n;
	vec2 cell = floor(p);
	vec2 f = p - cell - 0.5;

	// Случайные числа плиты — от её номера и положения узла: одна и та же деталь
	// в разных клетках раскладывается по-разному, а развёртка у всех копий общая.
	vec3 h = hash33(vec3(cell, 0.0) + NODE_POSITION_WORLD * 1.618);
	int k = min(int(h.z * 8.0), 7);
	int turns = k & 3;
	float c = turns == 0 ? 1.0 : (turns == 2 ? -1.0 : 0.0);
	float s = turns == 1 ? 1.0 : (turns == 3 ? -1.0 : 0.0);
	float m = k >= 4 ? -1.0 : 1.0;
	// D = R·M: зеркало по u, потом поворот на четверти.
	mat2 d = mat2(vec2(c, s), vec2(-s, c)) * mat2(vec2(m, 0.0), vec2(0.0, 1.0));

	vec2 slab = floor(h.xy * n);
	vec2 uv = (slab + 0.5 + d * f) / n;
	// Производные — от сплошной развёртки, повёрнутые той же матрицей: у uv на
	// шве скачок, и мипмап по нему выбрал бы самый мелкий уровень — линия на шве.
	vec2 dx = d * dFdx(UV);
	vec2 dy = d * dFdy(UV);

	ALBEDO = textureGrad(albedo_tex, uv, dx, dy).rgb;
	ROUGHNESS = roughness;
	METALLIC = 0.0;

	// Нормаль плиты — в осях текстуры; в оси развёртки её возвращает D^T.
	// Зелёный канал OpenGL смотрит вверх по картинке, а v у Godot растёт вниз,
	// поэтому y переводится в оси uv и обратно сменой знака.
	vec2 g = textureGrad(normal_tex, uv, dx, dy).xy * 2.0 - 1.0;
	g.y = -g.y;
	g = transpose(d) * g;
	g.y = -g.y;
	// z движок восстанавливает из xy сам.
	NORMAL_MAP = vec3(g * 0.5 + 0.5, 1.0);
	NORMAL_MAP_DEPTH = normal_depth;
}
