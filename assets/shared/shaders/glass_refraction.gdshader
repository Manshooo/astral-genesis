// Стекло с экранным преломлением, у которого сдвиг фона задан в метрах, а не в
// долях экрана.
//
// Встроенная Refraction у StandardMaterial3D сдвигает выборку копии экрана на
// постоянную долю экрана, сколько бы ни было до стекла: колба вдали мала на
// экране, а сдвиг тот же, и фон за ней ломается тем сильнее, чем дальше камера
// (известная беда экранного преломления, godot-proposals#9580). Здесь сдвиг —
// видимое смещение в метрах на глубине стекла, переведённое в экран проекцией
// и делённое на расстояние: вдали он уменьшается вместе со стеклом.
//
// Остальное повторяет BaseMaterial3D с refraction_enabled, чтобы стекло не
// поменяло вида: выборка копии экрана с мипа roughness × 8, глубина под сдвигом
// не даёт затянуть в преломление то, что перед стеклом, ALPHA = 1 и запись
// глубины. Из этого следует то же, что у встроенного: прозрачное за стеклом
// не видно (копия снята до прохода прозрачных), поэтому всё, что должно
// просвечивать, — непрозрачно (пузырьки колбы инкубатора).
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(0.78, 0.82, 0.86, 0.14);
uniform float specular : hint_range(0.0, 1.0, 0.01) = 0.9;
uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.18;
// Видимый сдвиг фона за стеклом, м. 0.1 м на 3.4 м от камеры (кадр главного
// меню) — те же 0.03 экрана, что давала встроенная refraction_scale 0.03.
uniform float refraction_shift : hint_range(0.0, 0.5, 0.001) = 0.1;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;


void fragment() {
	ALBEDO = albedo.rgb;
	SPECULAR = specular;
	ROUGHNESS = roughness;

	// Метр на глубине стекла в долях экрана: половина проекции на расстояние.
	vec2 metre_to_screen = vec2(PROJECTION_MATRIX[0][0], PROJECTION_MATRIX[1][1]) * 0.5 / max(-VERTEX.z, 0.05);
	vec2 ref_ofs = SCREEN_UV - NORMAL.xy * refraction_shift * metre_to_screen;
	float ref_amount = 1.0 - albedo.a;

	// Под сдвигом лежит то, что ближе стекла, — берём несдвинутый пиксель, иначе
	// предмет перед стеклом отразился бы в нём. Плавно, чтобы не было шва.
	float behind_depth = textureLod(depth_texture, ref_ofs, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec4 behind_ndc = vec4(vec3(ref_ofs, behind_depth) * 2.0 - 1.0, 1.0);
#else
	vec4 behind_ndc = vec4(ref_ofs * 2.0 - 1.0, behind_depth, 1.0);
#endif
	vec4 behind = INV_PROJECTION_MATRIX * behind_ndc;
	behind.xyz /= behind.w;
	vec2 uv = mix(SCREEN_UV, ref_ofs, smoothstep(0.0, 1.0, VERTEX.z - behind.z));

	EMISSION = textureLod(screen_texture, uv, ROUGHNESS * 8.0).rgb * ref_amount * EXPOSURE;
	ALBEDO *= 1.0 - ref_amount;
	ALPHA = 1.0;
}
