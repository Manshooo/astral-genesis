// Размытие строки-мысли при появлении и растворении (§6 «HUD — спека»).
// Висит на CanvasGroup, а не на Label: шейдер подписи видит атлас шрифта, и
// размытие тянуло бы в букву соседние глифы атласа. Группа сначала рисует
// строку целиком в свой буфер — размывается уже готовая картинка.
// Мипы + кольцо отсчётов: один textureLod даёт квадратную «лесенку», кольцо
// сглаживает её, а на 0–5 px дороже и не нужно.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float blur_px : hint_range(0.0, 8.0) = 0.0;

void fragment() {
	vec4 c;
	if (blur_px < 0.05) {
		c = textureLod(screen_tex, SCREEN_UV, 0.0);
	} else {
		float lod = log2(1.0 + blur_px * 0.5);
		vec2 r = blur_px * SCREEN_PIXEL_SIZE;
		c = textureLod(screen_tex, SCREEN_UV, lod) * 0.2;
		for (int i = 0; i < 8; i++) {
			float a = float(i) * TAU / 8.0;
			c += textureLod(screen_tex, SCREEN_UV + vec2(cos(a), sin(a)) * r, lod) * 0.1;
		}
	}
	// Буфер группы — с умноженной альфой; без деления края букв темнеют.
	if (c.a > 0.0001) {
		c.rgb /= c.a;
	}
	COLOR *= c;
}
