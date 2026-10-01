# Кадры-наброски живых 3D-сцен за меню и знак комплекса.
import math
import random
import re

# Знак комплекса в поле 250×250 (по assets/textures/complex-logo.jpg): вертикальный штрих,
# горизонтальная ветвь с поперечинами и две изогнутые нижние ветви с поперечинами.
LOGO_D = ("M125 22 V106 M38 90 H212 M27 72 L45 106 M223 72 L205 106 "
	"M125 98 C123 138 96 164 62 190 M125 98 C127 138 154 164 188 190 "
	"M46 174 L78 206 M204 174 L172 206")


def logo_transformed(cx, cy, s):
	"""Тот же путь знака, перенесённый в координаты экрана (центр знака — (cx, cy), масштаб s)."""
	tokens = re.findall(r"[MVHLC]|-?\d+(?:\.\d+)?", LOGO_D)
	out, cmd, nums = [], None, []

	def flush():
		if cmd is None:
			return
		if cmd == "V":
			out.append("V%.1f" % ((nums[0] - 125) * s + cy))
		elif cmd == "H":
			out.append("H%.1f" % ((nums[0] - 125) * s + cx))
		else:
			pts = []
			for i in range(0, len(nums), 2):
				pts.append("%.1f %.1f" % ((nums[i] - 125) * s + cx, (nums[i + 1] - 125) * s + cy))
			out.append(cmd + " ".join(pts))

	for tk in tokens:
		if tk in "MVHLC":
			flush()
			cmd, nums = tk, []
		else:
			nums.append(float(tk))
	flush()
	return " ".join(out)


def _grain(fid):
	return ('<filter id="%s" x="0" y="0" width="1497" height="720" filterUnits="userSpaceOnUse">'
		'<feTurbulence type="fractalNoise" baseFrequency=".9" numOctaves="2" stitchTiles="stitch"></feTurbulence>'
		'<feColorMatrix type="matrix" values="1 0 0 0 0  1 0 0 0 0  1 0 0 0 0  0 0 0 0 .55"></feColorMatrix></filter>') % fid


def menu_scene_a():
	"""A: операционная, вид души из-под потолка. Тело под простынёй, бак, где держали мозг."""
	rnd = random.Random(7)
	s = ['<svg width="1497" height="720" viewBox="0 0 1497 720" style="position:absolute;left:0;top:0">',
		'<defs>',
		'<linearGradient id="ma-floor" x1="0" y1="470" x2="0" y2="720" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#1d2221"></stop><stop offset="1" stop-color="#0c0e0e"></stop></linearGradient>',
		'<linearGradient id="ma-lw" x1="0" y1="0" x2="840" y2="0" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#0a0c0c"></stop><stop offset="1" stop-color="#1a1f1e"></stop></linearGradient>',
		'<linearGradient id="ma-rw" x1="1497" y1="0" x2="1240" y2="0" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#0b0d0d"></stop><stop offset="1" stop-color="#1a1f1e"></stop></linearGradient>',
		'<linearGradient id="ma-cone" x1="0" y1="172" x2="0" y2="620" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#E8ECEA" stop-opacity=".20"></stop><stop offset="1" stop-color="#E8ECEA" stop-opacity="0"></stop></linearGradient>',
		'<linearGradient id="ma-sheet" x1="0" y1="510" x2="0" y2="585" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#a7afab" stop-opacity=".62"></stop><stop offset="1" stop-color="#39403e" stop-opacity=".9"></stop></linearGradient>',
		'<radialGradient id="ma-tank" cx="725" cy="440" r="70" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#C9A8F2" stop-opacity=".42"></stop><stop offset="1" stop-color="#C9A8F2" stop-opacity="0"></stop></radialGradient>',
		'<radialGradient id="ma-pool" cx="1040" cy="600" r="300" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#d9dfdc" stop-opacity=".10"></stop><stop offset="1" stop-color="#d9dfdc" stop-opacity="0"></stop></radialGradient>',
		'<radialGradient id="ma-fog" cx="1040" cy="380" r="560" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#2b3331" stop-opacity=".35"></stop><stop offset="1" stop-color="#000" stop-opacity="0"></stop></radialGradient>',
		'<filter id="ma-blur" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="8"></feGaussianBlur></filter>',
		_grain("ma-grain"),
		'</defs>',
		'<rect x="0" y="0" width="1497" height="720" fill="#0a0b0b"></rect>',
		'<polygon points="0,0 1497,0 1240,190 840,190" fill="#0c0e0e"></polygon>',
		'<polygon points="0,720 1497,720 1240,470 840,470" fill="url(#ma-floor)"></polygon>',
		'<polygon points="0,0 840,190 840,470 0,720" fill="url(#ma-lw)"></polygon>',
		'<polygon points="1497,0 1240,190 1240,470 1497,720" fill="url(#ma-rw)"></polygon>',
		'<rect x="840" y="190" width="400" height="280" fill="#161a19"></rect>',
		'<rect x="930" y="250" width="220" height="82" fill="#0b0e0d" stroke="#2a312f" stroke-width="2"></rect>',
		'<line x1="1040" y1="250" x2="1040" y2="332" stroke="#2a312f" stroke-width="2"></line>',
		'<polygon points="940,260 990,260 960,322 940,322" fill="#E8ECEA" opacity=".03"></polygon>']
	# плитка пола к точке схода
	for k in range(0, 9):
		xb = 840 + k * 50
		xf = 1040 + (xb - 1040) * 3.6
		s.append('<line x1="%d" y1="470" x2="%.0f" y2="720" stroke="#0a0c0c" stroke-width="1.4" opacity=".8"></line>' % (xb, xf))
	for y in (492, 522, 566, 632, 716):
		k = (y - 470) / 250.0
		xl = 840 - 840 * k
		xr = 1240 + 257 * k
		s.append('<line x1="%.0f" y1="%d" x2="%.0f" y2="%d" stroke="#0a0c0c" stroke-width="1.2" opacity=".7"></line>' % (xl, y, xr, y))
	# трубы по правой стене
	s.append('<polygon points="1497,96 1240,236 1240,242 1497,112" fill="#1f2524"></polygon>')
	s.append('<polygon points="1497,140 1240,258 1240,262 1497,150" fill="#1b201f"></polygon>')
	# пятно света, конус лампы
	s.append('<ellipse cx="1040" cy="600" rx="300" ry="64" fill="url(#ma-pool)"></ellipse>')
	s.append('<g class="ag-lamp"><polygon points="1000,172 1080,172 1300,620 780,620" fill="url(#ma-cone)"></polygon>')
	s.append('<line x1="1040" y1="0" x2="1040" y2="150" stroke="#1a1f1e" stroke-width="2"></line>')
	s.append('<polygon points="1010,150 1070,150 1086,172 994,172" fill="#1c2120"></polygon>')
	s.append('<ellipse cx="1040" cy="173" rx="34" ry="6" fill="#F2EEF7" opacity=".55" filter="url(#ma-blur)"></ellipse>')
	s.append('<ellipse cx="1040" cy="172" rx="16" ry="2.5" fill="#F7F5F2" opacity=".9"></ellipse></g>')
	# бак для мозга — пустой, сиреневое свечение там, где была душа
	s.append('<rect x="688" y="372" width="74" height="12" fill="#232928"></rect>')
	s.append('<rect x="694" y="384" width="62" height="128" rx="5" fill="#0f1312" stroke="#46514e" stroke-width="1.6"></rect>')
	s.append('<rect x="696" y="420" width="58" height="90" rx="4" fill="url(#ma-tank)"></rect>')
	s.append('<line x1="702" y1="392" x2="702" y2="500" stroke="#E8ECEA" stroke-width="1.5" opacity=".08"></line>')
	s.append('<rect x="682" y="512" width="86" height="14" fill="#1a1f1e"></rect>')
	s.append('<line x1="725" y1="526" x2="725" y2="660" stroke="#121615" stroke-width="5"></line>')
	s.append('<path d="M760 470 C800 478 832 498 858 530" fill="none" stroke="#2b3231" stroke-width="2"></path>')
	s.append('<path d="M756 488 C796 500 830 520 860 540" fill="none" stroke="#252b2a" stroke-width="1.6"></path>')
	for i, (x0, dx) in enumerate(((712, -10), (726, 6), (740, -4))):
		pts = []
		for j in range(14):
			yy = 372 - j * 9
			pts.append("%.1f %.1f" % (x0 + dx * math.sin(j * .6 + i) + 3 * math.sin(j * 1.7 + i * 2), yy))
		s.append('<path class="ag-wisp" style="animation-delay:-%.1fs" d="M%s" fill="none" stroke="#C9A8F2" stroke-width="1.1" stroke-linecap="round" opacity=".5"></path>' % (i * 1.4, " L".join(pts)))
	# каталка с телом под простынёй
	s.append('<polygon points="850,520 1230,520 1290,585 790,585" fill="#202625"></polygon>')
	s.append('<rect x="790" y="585" width="500" height="12" fill="#141817"></rect>')
	for x1, x2, y2 in ((822, 824, 700), (1258, 1256, 700), (884, 886, 668), (1196, 1194, 668)):
		s.append('<line x1="%d" y1="597" x2="%d" y2="%d" stroke="#0e1111" stroke-width="4"></line>' % (x1, x2, y2))
	s.append('<path d="M824 574 C850 540 892 524 944 530 C986 516 1042 512 1100 524 C1152 518 1214 530 1262 572 Z" fill="url(#ma-sheet)"></path>')
	s.append('<ellipse cx="884" cy="534" rx="38" ry="20" fill="#9aa29e" opacity=".55"></ellipse>')
	s.append('<path d="M824 574 C900 566 1000 570 1100 566 C1170 564 1230 568 1262 572" fill="none" stroke="#0f1212" stroke-width="1.4" opacity=".6"></path>')
	# пыль в луче
	for i in range(16):
		x = rnd.uniform(860, 1220)
		y = rnd.uniform(260, 560)
		cls = "ag-dust-l" if i % 2 else "ag-dust-r"
		s.append('<circle class="%s" style="animation-delay:-%.1fs" cx="%.0f" cy="%.0f" r="%.1f" fill="#F2EEF7" opacity=".7"></circle>' % (cls, rnd.uniform(0, 8), x, y, rnd.uniform(.8, 1.6)))
	s.append('<rect x="0" y="0" width="1497" height="720" fill="url(#ma-fog)"></rect>')
	s.append('<rect x="0" y="0" width="1497" height="720" filter="url(#ma-grain)" opacity=".06"></rect>')
	s.append('<rect x="0" y="0" width="1497" height="720" fill="none"></rect>')
	s.append('</svg>')
	s.append('<div style="position:absolute;left:0;top:0;width:1497px;height:720px;pointer-events:none;background:radial-gradient(ellipse 70% 80% at 62% 50%, rgba(18,10,30,0) 40%, rgba(18,10,30,.9) 100%)"></div>')
	return "".join(s)


def menu_scene_b():
	"""B: пультовая. Стена мёртвых мониторов, один живой — заставка со знаком и широкими серыми полосами."""
	s = ['<svg width="1497" height="720" viewBox="0 0 1497 720" style="position:absolute;left:0;top:0">',
		'<defs>',
		'<clipPath id="mb-live"><rect x="1014" y="164" width="162" height="112" rx="14"></rect></clipPath>',
		'<clipPath id="mb-st"><rect x="804" y="334" width="162" height="112" rx="14"></rect></clipPath>',
		'<radialGradient id="mb-glow" cx="1095" cy="220" r="260" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#cfd4d0" stop-opacity=".16"></stop><stop offset="1" stop-color="#cfd4d0" stop-opacity="0"></stop></radialGradient>',
		'<radialGradient id="mb-desk" cx="1095" cy="610" r="300" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#cfd4d0" stop-opacity=".09"></stop><stop offset="1" stop-color="#cfd4d0" stop-opacity="0"></stop></radialGradient>',
		'<linearGradient id="mb-sheen" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#E8EAE6" stop-opacity=".06"></stop><stop offset=".5" stop-color="#E8EAE6" stop-opacity="0"></stop></linearGradient>',
		'<filter id="mb-static" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency=".85 .35" numOctaves="1" seed="4"></feTurbulence><feColorMatrix type="matrix" values="0 0 0 0 .8  0 0 0 0 .82  0 0 0 0 .8  0 0 0 1.3 -.45"></feColorMatrix></filter>',
		_grain("mb-grain"),
		'</defs>',
		'<rect x="0" y="0" width="1497" height="720" fill="#070808"></rect>',
		'<rect x="680" y="70" width="817" height="530" fill="#0b0d0d"></rect>',
		'<rect x="0" y="0" width="1497" height="720" fill="url(#mb-glow)"></rect>']
	cols = (790, 1000, 1210)
	rows = (150, 320)
	for ri, y in enumerate(rows):
		for ci, x in enumerate(cols):
			s.append('<rect x="%d" y="%d" width="190" height="140" rx="12" fill="#111413" stroke="#1c201f" stroke-width="2"></rect>' % (x, y))
			s.append('<rect x="%d" y="%d" width="162" height="112" rx="14" fill="#040505"></rect>' % (x + 14, y + 14))
			s.append('<rect x="%d" y="%d" width="162" height="112" rx="14" fill="url(#mb-sheen)"></rect>' % (x + 14, y + 14))
			s.append('<circle cx="%d" cy="%d" r="2" fill="#1f2423"></circle>' % (x + 176, y + 132))
	# живой экран: знак + полосы
	s.append('<g clip-path="url(#mb-live)"><rect x="1014" y="164" width="162" height="112" fill="#0d0f0f"></rect>')
	s.append('<g class="tm-logo-anim"><g transform="translate(1059 184) scale(.29)"><path d="%s" fill="none" stroke="#E8EAE6" stroke-width="16" stroke-linecap="round" stroke-linejoin="round"></path></g></g>' % LOGO_D)
	s.append('<rect class="tm-sb" x="1014" y="140" width="162" height="34" fill="#9aa09d" opacity=".28"></rect>')
	s.append('<rect class="tm-sb2" x="1014" y="140" width="162" height="18" fill="#9aa09d" opacity=".2"></rect>')
	for yy in range(166, 276, 3):
		s.append('<line x1="1014" y1="%d" x2="1176" y2="%d" stroke="#000" stroke-width="1" opacity=".35"></line>' % (yy, yy))
	s.append('</g>')
	s.append('<rect x="1014" y="164" width="162" height="112" rx="14" fill="none" stroke="#E8EAE6" stroke-opacity=".06" stroke-width="6"></rect>')
	# экран со снегом
	s.append('<g clip-path="url(#mb-st)"><rect x="804" y="334" width="162" height="112" filter="url(#mb-static)" opacity=".35"></rect></g>')
	# экран с журналом
	for i, w in enumerate((96, 120, 70, 132, 88, 54, 110)):
		s.append('<rect x="1228" y="%d" width="%d" height="3" fill="#8C918D" opacity="%.2f"></rect>' % (348 + i * 13, w, .42 - i * .04))
	s.append('<rect x="1228" y="440" width="7" height="3" fill="#8C918D" class="tm-cursor"></rect>')
	# кабели
	s.append('<path d="M880 290 C870 340 850 360 860 330" fill="none" stroke="#141716" stroke-width="3"></path>')
	s.append('<path d="M1100 460 C1090 530 1120 560 1080 600" fill="none" stroke="#121514" stroke-width="4"></path>')
	s.append('<path d="M1300 460 C1310 520 1280 560 1320 600" fill="none" stroke="#121514" stroke-width="3"></path>')
	# пульт
	s.append('<polygon points="640,600 1497,600 1497,720 560,720" fill="#0d0f0f"></polygon>')
	s.append('<line x1="640" y1="600" x2="1497" y2="600" stroke="#232827" stroke-width="2"></line>')
	s.append('<ellipse cx="1095" cy="612" rx="300" ry="34" fill="url(#mb-desk)"></ellipse>')
	s.append('<polygon points="990,624 1200,624 1212,656 978,656" fill="#141716"></polygon>')
	for k in range(1, 12):
		s.append('<line x1="%.0f" y1="626" x2="%.0f" y2="654" stroke="#0b0d0d" stroke-width="1"></line>' % (990 + k * 17.5, 978 + k * 19.5))
	s.append('<line x1="984" y1="640" x2="1206" y2="640" stroke="#0b0d0d" stroke-width="1"></line>')
	s.append('<circle cx="1390" cy="616" r="9" fill="#C4574A" opacity=".16"></circle>')
	s.append('<circle cx="1390" cy="616" r="2.6" fill="#C4574A"></circle>')
	s.append('<rect x="0" y="0" width="1497" height="720" filter="url(#mb-grain)" opacity=".07"></rect>')
	s.append('</svg>')
	return "".join(s)


def summary_scene_a():
	"""A: пустота, в которой рассеиваются осколки души."""
	rnd = random.Random(11)
	s = ['<div style="position:absolute;left:0;top:0;width:1497px;height:720px;background:radial-gradient(ellipse 60% 70% at 50% 28%, #17131f, #0B0A0D 72%)"></div>',
		'<svg width="1497" height="720" viewBox="0 0 1497 720" style="position:absolute;left:0;top:0;pointer-events:none">']
	for i in range(34):
		x = rnd.uniform(260, 1240)
		y = rnd.uniform(150, 700)
		cls = "ag-dust-l" if i % 2 else "ag-dust-r"
		s.append('<circle class="%s" style="animation-delay:-%.1fs" cx="%.0f" cy="%.0f" r="%.1f" fill="#C9A8F2" opacity=".6"></circle>' % (cls, rnd.uniform(0, 8.5), x, y, rnd.uniform(.9, 2.2)))
	s.append('</svg>')
	return "".join(s)


def game_scene(hud_main_html):
	"""Кадр коридора из HUD-холста — фон для паузы, навыков и карты в забеге."""
	i = hud_main_html.index('<svg width="1497" height="720"')
	j = hud_main_html.index("</svg>", i) + 6
	return hud_main_html[i:j].replace("ca-", "gm-")
