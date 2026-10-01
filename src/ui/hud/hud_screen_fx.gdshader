// Эффекты экрана HUD «Отголосок» (§11 «HUD — спека»): распад души или тела,
// кровь при малом HP, отклик удара и волна вселения — одним проходом.
// Один проход, а не стопка ColorRect: без BackBufferCopy каждый из них читал бы
// один и тот же снимок экрана, и эффекты не складывались бы друг с другом.
// Юниформы выставляет UI_HudScreenFx каждый кадр; шейдер ничего не решает сам.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform sampler2D blot_tex : repeat_enable, filter_linear;
uniform float vignette : hint_range(0.0, 1.0) = 0.12;
uniform vec3 vignette_color : source_color = vec3(0.07, 0.04, 0.12);
uniform float desaturation : hint_range(0.0, 1.0) = 0.15;
uniform vec3 desat_tint : source_color = vec3(1.0);
uniform float distortion_px : hint_range(0.0, 6.0) = 0.0;
uniform float chroma_px : hint_range(0.0, 4.0) = 0.0;
uniform float blood : hint_range(0.0, 1.0) = 0.0;
uniform vec3 blood_color : source_color = vec3(0.43, 0.05, 0.05);
uniform float edge_dark : hint_range(0.0, 1.0) = 0.0;
uniform vec2 shake_px = vec2(0.0);
uniform float shine : hint_range(0.0, 1.0) = 0.0;
uniform vec3 shine_color : source_color = vec3(0.79, 0.66, 0.95);
// Раскладка пятен крови: (сдвиг x, сдвиг y, поворот). Каждый удар кладёт новую,
// и прежняя перетекает в неё за blot_mix — иначе пятна стояли бы одним узором
// весь забег и выдавали бы текстуру.
uniform vec3 blot_from = vec3(0.0);
uniform vec3 blot_to = vec3(0.0);
uniform float blot_mix : hint_range(0.0, 1.0) = 1.0;

// Поворот — вокруг центра экрана и в пикселях, а не в UV: в UV широкий экран
// крутился бы эллипсом, и пятна сплющивались бы по диагонали.
float blot_at(vec2 uv, vec3 layout, float aspect) {
	vec2 p = (uv - 0.5) * vec2(aspect, 1.0);
	float s = sin(layout.z);
	float c = cos(layout.z);
	p = vec2(c * p.x - s * p.y, s * p.x + c * p.y);
	return texture(blot_tex, p / vec2(aspect, 1.0) + 0.5 + layout.xy).r;
}

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec2 n = texture(noise_tex, SCREEN_UV * vec2(1.0, 0.5) + TIME * vec2(0.02, 0.035)).rg - 0.5;
	vec2 uv = SCREEN_UV + shake_px * px + n * 2.0 * distortion_px * px;
	vec2 ca = vec2(chroma_px, 0.0) * px;
	vec3 c = vec3(texture(screen_tex, uv + ca).r, texture(screen_tex, uv).g, texture(screen_tex, uv - ca).b);
	// Душа уходит в серое, тело — в сепию: кривая одна, тон разный.
	c = mix(c, dot(c, vec3(0.299, 0.587, 0.114)) * desat_tint, desaturation);

	// Эллипс как у макета: радиусы 72 % и 78 % экрана.
	float r = length((SCREEN_UV - 0.5) / vec2(0.72, 0.78));
	c = mix(c, vignette_color, smoothstep(0.38, 1.0, r) * vignette);

	// Тело: кровь пятнами по краю, а не ровным кругом, потом потемнение удара.
	// Одна плитка шума на экран: две по ширине повторяли узор слева и справа.
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float blot = mix(blot_at(SCREEN_UV, blot_from, aspect), blot_at(SCREEN_UV, blot_to, aspect), blot_mix);
	float rim = smoothstep(0.55, 1.05, r + (blot - 0.5) * 0.35);
	c = mix(c, blood_color * 0.6, rim * blood);
	c *= 1.0 - smoothstep(0.45, 1.0, r) * edge_dark;
	c = mix(c, shine_color, smoothstep(0.55, 1.0, r) * shine * 0.5);
	COLOR = vec4(c, 1.0);
}
