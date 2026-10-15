// Стекло колбы с жидкостью: экранное преломление, муть по толщине жидкости,
// свечение самой жидкости и медленное колыхание.
//
// Сдвиг фона задан в метрах, а не в долях экрана. Встроенная Refraction у
// StandardMaterial3D сдвигает выборку копии экрана на постоянную долю экрана,
// сколько бы ни было до стекла: колба вдали мала, а сдвиг тот же, и фон за ней
// ломается тем сильнее, чем дальше камера (godot-proposals#9580). Здесь сдвиг —
// видимое смещение в метрах на глубине стекла, переведённое в экран проекцией:
// вдали оно уменьшается вместе со стеклом. Колыхание — тот же сдвиг от шума,
// плывущего вверх в мировых координатах, чтобы рябь стояла в жидкости, а не
// ехала за камерой.
//
// Муть и свечение — здесь, а не объёмным туманом (FogVolume): объёмный туман
// включён не в каждом окружении, в хабе его нет, и колба там была бы пустой.
// Толщина жидкости — от стекла до того, что за ним, по буферу глубины
// (Бер — Ламберт), но не больше диаметра колбы: иначе сквозь колбу дальняя стена
// комнаты считалась бы «пятью метрами жидкости». Диаметр и пульс свечения —
// instance uniform: их задаёт колба своему экземпляру, общий .tres не трогается.
//
// Остальное повторяет BaseMaterial3D с refraction_enabled: выборка копии с мипа
// roughness × 8, глубина под сдвигом не даёт затянуть в преломление то, что
// перед стеклом, ALPHA = 1 и запись глубины. Отсюда то же ограничение, что у
// встроенного: прозрачное за стеклом не видно (копия снята до прохода
// прозрачных), поэтому всё, что должно просвечивать, — непрозрачно (пузырьки).
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

group_uniforms glass;
uniform vec4 albedo : source_color = vec4(0.78, 0.82, 0.86, 0.14);
uniform float specular : hint_range(0.0, 1.0, 0.01) = 0.9;
uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.18;
// Видимый сдвиг фона за стеклом, м. 0.1 м на 3.4 м от камеры (кадр главного
// меню) — те же 0.03 экрана, что давала встроенная refraction_scale 0.03.
uniform float refraction_shift : hint_range(0.0, 0.5, 0.001) = 0.1;

group_uniforms liquid;
// Цвет и сила свечения жидкости — в неё уходит фон по мере толщины.
uniform vec4 liquid_color : source_color = vec4(0.3, 0.24, 0.42, 1.0);
uniform float liquid_energy : hint_range(0.0, 4.0, 0.01) = 1.0;
// Мутность, 1/м: доля фона, прошедшая слой d, — exp(-density·d).
uniform float liquid_density : hint_range(0.0, 8.0, 0.01) = 0.8;
// Сколько мипов размытия добавляет полная муть: мутное — ещё и молочное.
uniform float murk_blur : hint_range(0.0, 4.0, 0.1) = 1.5;

group_uniforms sway;
uniform sampler2D sway_noise : hint_default_black, repeat_enable, filter_linear_mipmap;
// Сдвиг фона от ряби, м; шаг ряби — 1/sway_scale м; скорость подъёма, м/с.
uniform float sway_shift : hint_range(0.0, 0.2, 0.001) = 0.012;
uniform float sway_scale : hint_range(0.05, 8.0, 0.01) = 0.8;
uniform float sway_speed : hint_range(0.0, 1.0, 0.001) = 0.04;
group_uniforms;

// Пульс свечения (IncubatorFlask, 1 ± 12 %) и наибольшая толщина жидкости, м
// (диаметр колбы по её стеклу).
instance uniform float glow = 1.0;
instance uniform float liquid_depth = 1.3;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;


// Точка за пикселем [param uv] в пространстве камеры, по буферу глубины.
vec3 view_position(vec2 uv, mat4 inv_projection) {
	float depth = textureLod(depth_texture, uv, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec4 ndc = vec4(vec3(uv, depth) * 2.0 - 1.0, 1.0);
#else
	vec4 ndc = vec4(uv * 2.0 - 1.0, depth, 1.0);
#endif
	vec4 view = inv_projection * ndc;
	return view.xyz / view.w;
}


void fragment() {
	ALBEDO = albedo.rgb;
	SPECULAR = specular;
	ROUGHNESS = roughness;

	// Метр на глубине стекла в долях экрана: половина проекции на расстояние.
	vec2 metre_to_screen = vec2(PROJECTION_MATRIX[0][0], PROJECTION_MATRIX[1][1]) * 0.5 / max(-VERTEX.z, 0.05);
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 sway_uv = vec2(world.x + world.z, world.y) * sway_scale - vec2(0.0, TIME * sway_speed * sway_scale);
	// Шум серый (r = g = b): две выборки вразнос дают независимые x и y.
	vec2 sway = (vec2(texture(sway_noise, sway_uv).r, texture(sway_noise, sway_uv + vec2(0.37, 0.71)).r) - 0.5)
			* 2.0 * sway_shift;
	vec2 ref_ofs = SCREEN_UV - (NORMAL.xy * refraction_shift + sway) * metre_to_screen;
	float ref_amount = 1.0 - albedo.a;

	// Под сдвигом лежит то, что ближе стекла, — берём несдвинутый пиксель, иначе
	// предмет перед стеклом отразился бы в нём. Плавно, чтобы не было шва.
	vec3 behind_shifted = view_position(ref_ofs, INV_PROJECTION_MATRIX);
	vec2 uv = mix(SCREEN_UV, ref_ofs, smoothstep(0.0, 1.0, VERTEX.z - behind_shifted.z));

	float thickness = clamp(VERTEX.z - view_position(uv, INV_PROJECTION_MATRIX).z, 0.0, liquid_depth);
	float murk = 1.0 - exp(-liquid_density * thickness);

	vec3 background = textureLod(screen_texture, uv, ROUGHNESS * 8.0 + murk_blur * murk).rgb * EXPOSURE;
	vec3 liquid = liquid_color.rgb * liquid_energy * glow;
	EMISSION = mix(background, liquid, murk) * ref_amount;
	ALBEDO *= 1.0 - ref_amount;
	ALPHA = 1.0;
}
