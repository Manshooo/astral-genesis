// res://src/ui/menu/menu_backdrop.gdshader
// Фон под экранами меню (§8 «Меню — спека»). В забеге мир не закрывается окном, а
// «заволакивается», как мысль: размытие, обесцвечивание, затемнение и виньетка
// распада души из HUD, но статичная. Вне забега мира за экраном нет — глухой
// фон bg_void с тусклым пятном, как в прототипе (void_amount = 1).
// ColorRect на весь экран под содержимым экрана; HUD и обводка интерактива
// заволакиваются вместе с миром — на паузе их не читают.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
// Одна ручка входа и выхода: твин 0 → 1 за 220 мс.
uniform float amount : hint_range(0.0, 1.0) = 0.0;
// Размытие — мип-уровнем экрана: силуэты угадываются, детали не отвлекают.
uniform float blur_lod : hint_range(0.0, 5.0) = 2.6;
// Серость = остановленное время; сиреневое меню остаётся единственным цветом.
uniform float desaturate : hint_range(0.0, 1.0) = 0.7;
// bg_void α .66 — контраст текста не ниже 7:1 над любым кадром.
uniform vec4 scrim : source_color = vec4(0.043, 0.039, 0.051, 0.66);
uniform vec4 tint : source_color = vec4(0.071, 0.039, 0.118, 0.95);
uniform float vig_inner : hint_range(0.0, 1.5) = 0.30;
uniform float vig_outer : hint_range(0.0, 1.5) = 1.00;
// Вне забега: глухой фон вместо мира.
uniform float void_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 void_color : source_color = vec4(0.043, 0.039, 0.051, 1.0);
uniform vec4 void_glow : source_color = vec4(0.082, 0.071, 0.106, 1.0);

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, blur_lod * amount).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(l), desaturate * amount);
	c = mix(c, scrim.rgb, scrim.a * amount);
	vec2 d = (SCREEN_UV - 0.5) / vec2(0.72, 0.78);
	float v = smoothstep(vig_inner, vig_outer, length(d) * 2.0);
	c = mix(c, tint.rgb, v * tint.a * amount);

	// Пятно глухого фона — эллипс 80 × 90 % с центром в (30 %, 40 %).
	vec2 g = (SCREEN_UV - vec2(0.3, 0.4)) / vec2(0.8, 0.9);
	vec3 void_c = mix(void_glow.rgb, void_color.rgb, smoothstep(0.0, 0.7, length(g) * 2.0));
	c = mix(c, void_c, void_amount * amount);
	COLOR = vec4(c, 1.0);
}
