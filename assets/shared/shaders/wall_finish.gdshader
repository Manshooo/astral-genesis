// Отделка стены без развёртки: тайл 2 × 2 м из мира, пояс у пола и поле над ним.
//
// Карты — tools/room_textures.py арт-репозитория: рисунок (панели, филёнки, швы)
// нарисован прямо в тайле, поэтому гекс-тайлинга, как у wall_layers, здесь нет —
// он раздвоил бы прямые швы. Повтор гасят тон плиты по номеру тайла и макро-пятна.
//
// Проекция — как у wall_layers: плоскость на грань по нормали, метры мира, картинка
// верхом вверх; горизонтальные грани проецируются сверху. Сетка сдвинута на толщину
// стены (offset_m.x), чтобы шов тайла ложился во внутренний угол комнаты: центры
// клеток в кратных 8 м, тайл 2 м, без сдвига шов ушёл бы в толщу соседней стены.
//
// По высоте от пола уровня (NODE_POSITION_WORLD — пол детали, кратно level_height_m):
// 0…low_height_m — пояс (_wall_low: плинтус, филёнки, отбойник), выше — поле
// (_wall), тайлится во все стороны. Пояса нет (use_low = false) — поле от пола.
// Верх тайла пояса стыкуется с низом тайла поля: генератор кладёт у пары общее зерно.
shader_type spatial;

group_uniforms field;
uniform sampler2D field_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D field_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D field_roughness : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

group_uniforms low;
uniform bool use_low = false;
uniform sampler2D low_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D low_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D low_roughness : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
// Высота пояса = один тайл: карта пояса нарисована на 0…2 м от пола.
uniform float low_height_m = 2.0;

group_uniforms layout;
// Метров на тайл (room_textures.json, tex_m).
uniform float tex_m = 2.0;
// Сдвиг сетки: по ширине — толщина стены кита (Метрики и кит §2), как panel_offset_m у wall_layers.
uniform vec2 offset_m = vec2(0.25, 0.0);
uniform float level_height_m = 8.0;

group_uniforms variation;
// Разброс тона между тайлами 2 м: тайл ставится повсюду одинаковым, и ровный тон выдал бы сетку.
uniform float tile_tone : hint_range(0.0, 0.2) = 0.03;
uniform float macro_size_m = 7.0;
uniform float macro_albedo : hint_range(0.0, 0.5) = 0.08;
uniform float macro_roughness : hint_range(0.0, 0.5) = 0.05;
// Низ темнее (Визуальный стиль §2.1): тайлы без запечённого объёма комнаты.
uniform float grime_height_m = 1.5;
uniform float grime_strength : hint_range(0.0, 1.0) = 0.2;

group_uniforms;
uniform float normal_depth : hint_range(0.0, 4.0) = 1.0;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = MODEL_NORMAL_MATRIX * NORMAL;
}

// Hash without Sine, Dave Hoskins (MIT) — как в wall_layers.
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

vec3 unpack_z(vec2 xy) {
	// Карты нормалей сжаты в два канала (RGTC), z восстанавливается из xy.
	return vec3(xy, sqrt(max(0.0, 1.0 - dot(xy, xy))));
}

void fragment() {
	vec3 n = normalize(world_normal);
	bool flat_face = abs(n.y) > 0.7;
	vec3 right = flat_face ? vec3(1.0, 0.0, 0.0) : normalize(vec3(n.z, 0.0, -n.x));
	vec3 up = normalize(cross(n, right));
	vec2 q = vec2(dot(world_pos, right), dot(world_pos, up));
	vec2 dqx = dFdx(q);
	vec2 dqy = dFdy(q);
	float plane = floor(dot(world_pos, n) * 4.0 + 0.5);

	// Высота от пола уровня. У вертикальной грани она же — ось картинки вверх.
	float h = mod(world_pos.y - NODE_POSITION_WORLD.y, level_height_m);
	// v картинки: 0 — верх тайла. Тайл пояса стоит на полу (низ картинки на h = 0),
	// поле продолжает ту же сетку вверх, поэтому формула одна.
	float qy = flat_face ? q.y : h;
	vec2 uv = vec2((q.x - offset_m.x) / tex_m, (low_height_m - qy + offset_m.y) / tex_m);
	vec2 duvx = vec2(dqx.x, -dqx.y) / tex_m;
	vec2 duvy = vec2(dqy.x, -dqy.y) / tex_m;

	bool in_low = use_low && !flat_face && h < low_height_m;
	vec3 albedo;
	vec2 nxy;
	float rough;
	if (in_low) {
		albedo = textureGrad(low_albedo, uv, duvx, duvy).rgb;
		nxy = textureGrad(low_normal, uv, duvx, duvy).xy * 2.0 - 1.0;
		rough = textureGrad(low_roughness, uv, duvx, duvy).r;
	} else {
		albedo = textureGrad(field_albedo, uv, duvx, duvy).rgb;
		nxy = textureGrad(field_normal, uv, duvx, duvy).xy * 2.0 - 1.0;
		rough = textureGrad(field_roughness, uv, duvx, duvy).r;
	}

	// Тон тайла: по горизонтали — свой у каждого, по вертикали пояс и поле отдельно.
	vec2 tile = floor(vec2(uv.x, in_low ? -1.0 : floor(uv.y)));
	float tone = 1.0 + (hash13(vec3(tile, plane)) - 0.5) * 2.0 * tile_tone;

	vec2 mq = (q + plane * vec2(0.37, 0.61)) / macro_size_m;
	float macro = 0.65 * value_noise(mq, 11.0) + 0.35 * value_noise(mq * 2.3, 17.0);
	float grime = 1.0 - smoothstep(0.0, grime_height_m, h);

	albedo *= tone;
	albedo *= 1.0 + (macro - 0.5) * 2.0 * macro_albedo;
	albedo *= 1.0 - grime_strength * grime;
	ALBEDO = albedo;
	ROUGHNESS = clamp(rough + (0.5 - macro) * 2.0 * macro_roughness, 0.0, 1.0);
	METALLIC = 0.0;

	// Нормаль собирается в мире: касательные меша построены по развёртке палитры,
	// где у всей грани одна точка UV, и NORMAL_MAP по ним не годится (как у wall_layers).
	vec3 t = unpack_z(nxy);
	t.xy *= normal_depth;
	t = normalize(t);
	vec3 nw = normalize(right * t.x + up * t.y + n * t.z);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
}
