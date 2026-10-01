# Спека переноса меню в Godot (язык A «Отголосок»).
# Тексты лежат один раз, в разметке markdown (`код`, **жирный**, *курсив*), и выводятся
# дважды: страницей холста Spec.dc.html и файлом .md для vault — чтобы они не разошлись.
import html
import re

CANVAS_URL = "https://claude.ai/artifact/JmJHkwGGCoYbWQXcS3ftxK"


def e(s):
	return html.escape(str(s), quote=True)


def lum(hexc):
	hexc = hexc.lstrip("#")
	rgb = [int(hexc[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
	lin = [c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb]
	return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]


def contrast(a, b):
	la, lb = lum(a), lum(b)
	hi, lo = max(la, lb), min(la, lb)
	return (hi + 0.05) / (lo + 0.05)


def blend(fg, bg, a):
	f = [int(fg.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4)]
	b = [int(bg.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4)]
	return "#%02X%02X%02X" % tuple(round(f[i] * a + b[i] * (1 - a)) for i in range(3))


def gcol(hexc, a=None):
	h = hexc.lstrip("#")
	r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
	if a is None:
		return "Color(%.2f, %.2f, %.2f)" % (r, g, b)
	return "Color(%.2f, %.2f, %.2f, %.2f)" % (r, g, b, a)


# ---------------------------------------------------------------- данные

BG = "#0B0A0D"

INTRO = [
	"Все меню — продолжение HUD: интерфейс как мысли бестелесной души. Без рамок и подложек, один шрифт Golos Text, сиреневый тон души #C9A8F2 на почти чёрном. Размеры — в пикселях базового окна **1497×720**; окно растягивается целыми кратными (`display/window/stretch/mode = canvas_items`, `display/window/stretch/scale_mode = integer`), поэтому все линии в 1 px остаются чёткими.",
	"**Почему A, а не B.** A — тот же голос, что у HUD: игрок не переключается между двумя интерфейсами, а меню в забеге «заволакивает» мир, а не закрывает его окном. B «Терминал X-16» сильнее как дизайн комплекса и легче читается в плотных экранах, поэтому из него взято одно: *сам знак комплекса* — в A он стал скелетом улучшений Архитектора. Если позже карту будут открывать только с терминала (`e_map_terminal`), экран карты можно перевести на язык B, не трогая остальные.",
]

PRINCIPLES = [
	"**Нет панелей.** Читаемость держит *тень мысли* — радиальное пятно #060509 α 0.55→0 за группой строк (`TextureRect` с `GradientTexture2D` radial), а в забеге — шейдер фона §8. Ни рамок, ни плашек, ни полос.",
	"**Сиреневое = внимание души.** Сиреневым окрашено только то, что держит фокус, выбрано или открыто: точка фокуса, штрих, эхо, открытые ранги, отметка игрока. Всё остальное — светло-серое.",
	"**Фокус с клавиатуры виден всегда и отличается от наведения.** Наведение: эхо + бледный штрих. Фокус: *точка души* слева + штрих в полную силу + эхо. После клика мышью фокус остаётся видимым — это допустимо.",
	"**Недоступное объясняет себя.** 28 % яркости, штрих — пунктир 1:3 (как пустой трек дуги HUD) и причина словами рядом: «нет сохранений», «Не хватает очков», «Сначала выполните требования».",
	"**Ширины по тексту.** Кнопки, вкладки и значения растут по содержимому (`size_flags = SHRINK_BEGIN`), колонки с фиксированной шириной переносят строки (`autowrap_mode = WORD_SMART`). Английский на 30 % длиннее ничего не ломает: проверено макетами EN.",
	"**Один механизм эха.** Эхо — копия строки soul α 0.30, сдвиг (2, 0) px, дрожит циклом 1.9 с. Это тот же T «смятения» HUD: при T = 0.6 амплитуда как здесь; когда смятение тает, эхо меню успокаивается вместе с HUD.",
]

PALETTE = [
	("bg_void", "#0B0A0D", None, "Фон вне забега, подложка экранов (не панели)"),
	("scrim", "#0B0A0D", 0.66, "Затемнение мира под паузой, навыками, картой (+ шейдер §8)"),
	("text", "#ECE8F2", None, "Текст в фокусе/наведении, значения"),
	("text_rest", "#ECE8F2", 0.74, "Кнопка-мысль в покое"),
	("text_msg", "#DCD6E4", None, "Подписи строк настроек, описания"),
	("text_dim", "#B4ADC0", None, "Вторичный текст, подсказки, «показатель» в итогах"),
	("text_off", "#ECE8F2", 0.28, "Недоступное (вместе с пунктиром 1:3 и причиной словами)"),
	("soul", "#C9A8F2", None, "Внимание души: точка фокуса, штрих, эхо (α 0.30), выбранное, открытые ранги"),
	("soul_key", "#D4B8F7", None, "Клавиша в [ ]; скобки — α 0.50"),
	("over", "#F1E8FF", None, "Вспышка отклика (открытие навыка, обмен клавиш)"),
	("dot", "#F2EEF7", None, "Бегунок слайдера, отметка игрока (как точка прицела HUD)"),
	("track", "#ECE8F2", 0.34, "Пунктир 1:3: пустой трек слайдера, пунктир недоступного, выноски итогов"),
	("shadow_blob", "#060509", 0.55, "Тень мысли за группой строк; у раскрытого списка — α 0.92 в центре"),
	("tint", "#120A1E", 0.95, "Виньетка шейдера фона (как распад души в HUD, но статичная)"),
]
NO_CONTRAST = ("bg_void", "scrim", "shadow_blob", "tint")
PALETTE_NOTE = "Текстовые пары проходят 4.5 : 1 с запасом; text_off (недоступное) намеренно ниже — его смысл несёт пунктир и подпись причины, не цвет. Красного в меню нет: красный в игре — тело и кровь."

FONT_NOTES = [
	"**Golos Text** (SIL OFL 1.1, вариативный wght 400–900) — кириллица и латиница одним шрифтом. Положить `assets/fonts/GolosText-VariableFont_wght.ttf`; начертания — `FontVariation` с `variation_opentype = {\"wght\": 500}` и т.п.; цифры в значениях и счётчиках — `opentype_features = {\"tnum\": 1}`. Трекинг в Godot задаётся `spacing_glyph` в пикселях — пересчитан ниже. Прописные — свойством `Label.uppercase`, а не капсом в строке перевода (ключи в CSV хранят обычный регистр).",
	"Проверить в шрифте глифы «» … — × и стрелки ↑↓←→ (имена клавиш стрелок). Если стрелок нет — подставлять SVG-иконку: имя клавиши и так приходит значением, а не текстом макета.",
]

TYPE = [
	("Название (меню)", "Title", "46", "600", "0.30 em → spacing_glyph 14", "56", "ПРОПИСНЫЕ", "text + эхо"),
	("Заголовок исхода (итоги)", "DeathTitle", "42", "600", "0.20 em → 8", "52", "ПРОПИСНЫЕ", "text + 2 эха"),
	("Кнопка-мысль", "EchoButton", "24", "500", "0", "30", "как в ключе", "text_rest → text"),
	("Кнопка малая (Отмена/Сброс/Применить, открыть ранг)", "EchoButtonSmall", "19", "500", "0", "26", "как в ключе", "text_rest → text"),
	("Вкладка", "TabBar", "19", "500", "0", "26", "как в ключе", "α .5 → text"),
	("Шёпот (заголовок экрана, подзаголовок)", "Whisper", "13", "600", "0.26 em → 3", "16", "ПРОПИСНЫЕ", "soul"),
	("Подпись строки настроек", "RowLabel", "16", "400", "0", "21", "как в ключе", "text_msg"),
	("Значение (слайдер, список)", "Value", "16", "500", "0, tnum", "21", "—", "text"),
	("Описание, подзаголовок итогов", "Body", "16–17", "400", "0", "23–24", "—", "text_msg"),
	("Подсказка / вторичное", "Caption", "13", "400", "0", "18", "—", "text_dim"),
	("Имя навыка у узла", "NodeName", "15", "500", "0", "19", "—", "text_msg → text"),
	("Ранг у узла «2/3», номер сборки", "Small", "12", "400", "0, tnum", "16", "—", "text_dim (сборка α .55)"),
	("Счётчик очков / эссенции", "Wallet", "40", "600", "0, tnum", "46", "—", "text"),
	("Имя навыка в карточке", "Title (вариант)", "26", "600", "0.02 em", "32", "—", "text + эхо"),
	("Клавиша в перепривязке", "KeyHint", "17", "600 (скобки 400)", "0", "22", "—", "soul_key, скобки α .5"),
	("Подписи карты (этаж, «срез»)", "MapLabel", "11", "600", "0.14 em → 2", "14", "ПРОПИСНЫЕ", "text_dim"),
]

GRID = [
	("Левое поле текста", "112. Кнопки начинаются с x 82: 30 px слева — место под точку фокуса"),
	("Правые поля", "96 — нижний ряд кнопок; 40 — подсказка [Esc] сверху справа (y 36)"),
	("Вертикальный ритм экрана", "шёпот-заголовок y 52 → вкладки y 80 → контент y 150 → нижние кнопки снизу 40"),
	("Кнопка-мысль", "min-height 44; content_margin L 30 · R 18 · T 6 · B 8 (малая: L 26 · R 14); между пунктами 4–6"),
	("Точка фокуса", "Ø 6 (малая Ø 5) в x 10 от левого края кнопки, по центру строки; ореол 5 px soul α .14"),
	("Рваный штрих", "1.2 px, soul; от x 30 до ширины − 18, на 4 px выше нижнего края; 15 изломов, амплитуда ±0.8 px"),
	("Эхо", "сдвиг (2, 0), дрожание (1.2…2.8, −0.4…0.6) за 1.9 с; размытие 0.3 px не обязательно"),
	("Вкладки", "высота 44, L 26 · R 14, между вкладками 18"),
	("Строка настройки", "высота 46; подпись 340 (перенос по словам), контрол с x 452"),
	("Слайдер", "320 × 24; трек 2 px; бегунок Ø 9 + ореол Ø 21; значение справа через 18, min-width 120"),
	("Флажок", "кольцо Ø 16, штрих 1.5; точка Ø 7; подпись «Вкл/Выкл» через 12"),
	("Выпадающий список", "высота 40, L 24 · R 10; шеврон 14; список: строки 36, тень мысли α .92, min-width 220"),
	("Перепривязка", "2 колонки, зазор 56; строка 40; [ клавиша ] 17 px; подпись ожидания 13 px слева от скобок"),
	("Подсказка строки", "колонка x 1060, ширина 330; заголовок 15/600, текст 14/20 text_dim"),
	("Итоги", "колонка 560 по центру; строка 34; выноска — пунктир 1:3, min 24; значение ≤ 300 справа"),
	("Навыки", "граф 80…1000 по x; узел — кнопка 44 × 44, ядро Ø 14, кольцо рангов r 17; подпись в 26 px от центра; карточка x 1060, ширина 340"),
	("Карта", "срез x 112, ширина 364, слой 90 (полоса 86); планы x 560, y 110, 840 × 490, зазор 28, клетка ≤ 34"),
]

THEME_INTRO = "Тема проекта (`assets/ui/menu_theme.tres`, подключить в `gui/theme/custom` вместо `assets/ui/defualt.theme`) задаёт цвета, шрифты, отступы и StyleBox; эхо и прорисовку штриха рисует `UI_EchoButton` — StyleBox текст копировать не умеет."

THEME = [
	("Button → вариация EchoButton (и EchoButtonSmall)", [
		("`styles/normal, pressed, disabled`", "StyleBoxEmpty, content_margin 30 / 6 / 18 / 8"),
		("`styles/hover`", "StyleBoxTexture `ui/menu/rag_hover.svg` (штрих α .55), texture_margin L 30 · R 18 · T 36 · B 8, axis_stretch_horizontal = TILE_FIT"),
		("`styles/focus`", "StyleBoxTexture `ui/menu/focus_echo.svg` 64 × 44: точка Ø 6 в (13, 22) с ореолом + штрих α 1 в нижней полосе; те же texture_margin — точка в неизменяемом углу, штрих тянется плиткой"),
		("`colors/font_color`", "`Color(0.93, 0.91, 0.95, 0.74)`"),
		("`font_hover_color, font_focus_color`", "`Color(0.93, 0.91, 0.95)`"),
		("`font_pressed_color, font_hover_pressed_color`", "`Color(0.79, 0.66, 0.95)` (soul)"),
		("`font_disabled_color`", "`Color(0.93, 0.91, 0.95, 0.28)`"),
		("`font_outline_color / outline_size`", "`Color(0, 0, 0, 0.55)` / 4 — только в вариации EchoButtonInRun (поверх мира)"),
		("`fonts/font, font_size`", "Golos 500 · 24 (малая 19)"),
		("`constants/h_separation`", "14 (иконка «Сохранено» от текста)"),
	]),
	("TabContainer / TabBar", [
		("`tab_unselected, tab_disabled`", "StyleBoxEmpty, content_margin 26 / 6 / 14 / 10"),
		("`tab_hovered`", "StyleBoxTexture rag_line.svg, modulate α .35"),
		("`tab_selected`", "StyleBoxTexture rag_line.svg α 1 + эхо (рисует скрипт вкладок, либо вкладки — ряд UI_EchoButton с ButtonGroup)"),
		("`tab_focus`", "focus_echo.svg (точка)"),
		("`panel, tabbar_background`", "StyleBoxEmpty"),
		("`font_selected_color / font_hovered_color / font_unselected_color / font_disabled_color`", "text · text α .85 · text α .50 · text α .28"),
		("`font_size, h_separation`", "19 · 18"),
	]),
	("HSlider", [
		("`slider`", "StyleBoxTexture `ui/menu/track_dotted.svg` 4 × 2 (1 px точка + 3 px пусто), TILE; content_margin T/B 1 → трек 2 px"),
		("`grabber_area, grabber_area_highlight`", "StyleBoxFlat bg soul, без скруглений, content_margin T/B 1"),
		("`icons/grabber`", "`ui/menu/slider_dot.svg` 22 × 22: точка Ø 9 #F2EEF7 + ореол Ø 21 α .10"),
		("`icons/grabber_highlight`", "`slider_dot_hl.svg`: точка soul + кольцо soul (наведение и фокус)"),
		("`icons/grabber_disabled`", "slider_dot.svg, modulate α .3"),
		("`constants/center_grabber, grabber_offset`", "0, 0"),
		("Фокус с клавиатуры", "Godot показывает grabber_highlight и на наведении, и на фокусе — поэтому фокус дублирует строка: UI_SettingRow при focus_entered потомка зажигает точку и эхо подписи"),
	]),
	("CheckBox, OptionButton, PopupMenu и прочее", [
		("CheckBox `icons/checked, unchecked`", "`check_on.svg` (кольцо Ø 16 штрих 1.5 + точка Ø 7 soul) · `check_off.svg` (кольцо α .6)"),
		("CheckBox `checked_disabled, unchecked_disabled`", "те же, α .3"),
		("CheckBox `styles/*`", "StyleBoxEmpty; focus — кольцо soul + ореол 5 px (`check_focus.svg`); h_separation 12; 16/500"),
		("OptionButton `styles/*`", "как EchoButton, content_margin L 24 · R 10; 16/500"),
		("OptionButton `icons/arrow, constants/modulate_arrow`", "`chevron.svg` 14 px · 1 (стрелка берёт цвет текста); arrow_margin 10; открыт — повернуть на 180°"),
		("PopupMenu `panel`", "StyleBoxFlat bg #060509 α .92, corner_radius 22, shadow_color #060509 α .70, shadow_size 26, content_margin 24 / 10 / 24 / 12 — читается как тень мысли, не плашка"),
		("PopupMenu `hover`", "StyleBoxEmpty; font_hover_color text; font_color text α .70"),
		("PopupMenu `icons/radio_checked, radio_unchecked`", "`dot_soul.svg` Ø 6 · пусто; v_separation 8; item_start_padding 16"),
		("ItemList (если список)", "panel, focus, selected, selected_focus, hovered — StyleBoxEmpty; cursor — focus_echo.svg; font_selected_color soul; font_hovered_color text; v_separation 6"),
		("Panel, PanelContainer", "StyleBoxEmpty везде"),
		("VScrollBar", "scroll — пунктир 1:3 вертикальный; grabber StyleBoxFlat soul α .6 ширина 2; grabber_highlight soul"),
		("TooltipPanel / TooltipLabel", "как panel PopupMenu · 14 px text_msg"),
	]),
]

ICONS_NOTE = "Все — SVG штрихом без заливки (точки — заливкой, это «точка души»), белые, цвет задаётся на месте через `modulate` или цвет темы. Папка `assets/ui/menu/`."
ICONS = [
	("chevron.svg", "M6 9l6 6 6-6", "шеврон списка"),
	("arrow_up.svg", "M12 19V5 M6 11l6-6 6 6", "портал вверх"),
	("arrow_down.svg", "M12 5v14 M6 13l6 6 6-6", "портал вниз"),
	("save.svg", "M4.5 4.5h11l4 4v11a1 1 0 0 1-1 1h-14a1 1 0 0 1-1-1v-14a1 1 0 0 1 1-1z M8 4.5v5h6v-5 M7 20.5v-6h10v6", "«Сохранено» (уже есть в assets/ui/icons)"),
	("rag_line.svg", "M1 12.4 L2.5 11.6 L4 12.8 L5.5 12.1 L7 13 L8.5 11.8 L10 12.5 L11.5 11.4 L13 12.7 L14.5 12 L16 13.1 L17.5 11.9 L19 12.6 L20.5 11.7 L23 12.3", "рваный штрих (плитка)"),
	("x16_sign.svg", None, "знак комплекса (Архитектор), поле 250×250"),
	("focus_echo.svg", "", "текстура фокуса 64×44: точка Ø 6 в (13, 22) + ореол Ø 16 α .14 + штрих в полосе y 38–42 от x 30"),
	("slider_dot.svg", "", "бегунок 22×22: точка Ø 9 + ореол Ø 21 α .10"),
	("check_on.svg / check_off.svg", "", "флажок 16×16: кольцо штрих 1.5 (+ точка Ø 7)"),
	("track_dotted.svg", "", "трек 4×2, плитка: 1 px точка + 3 px пусто"),
]

ANIM = [
	("Вход экрана", "260 мс", "ease-out (cubic .2,.7,.2,1)", "modulate.a 0→1, position.y +4→0; размытие 6→0 px прототипа в игре заменяет шейдер §8 (amount)", "Tween TRANS_CUBIC EASE_OUT"),
	("Выход экрана", "160 мс", "ease-in", "modulate.a 1→0", "Tween, затем queue_free / UIManager.close_top"),
	("Пауза: мир «заволакивает»", "220 мс", "ease-out", "шейдер §8: amount 0→1 (размытие, обесцвечивание, затемнение, виньетка)", "Tween на material.shader_parameter/amount"),
	("Пункты паузы", "по 30 мс задержки", "ease-out", "каждый следующий пункт входит на 30 мс позже", "Tween.set_delay(i * 0.03)"),
	("Наведение: эхо", "140 мс", "linear", "альфа эха 0→1; эхо дрожит циклом 1.9 с: (2,0)→(1.2,.6)→(2.8,−.4) px", "EchoButton: _process"),
	("Наведение: штрих", "220 мс", "ease-out", "рваный штрих прорисовывается слева направо (progress 0→1), α 0.55", "EchoButton._draw, draw_polyline до progress"),
	("Фокус с клавиатуры", "120 мс", "ease-out", "точка Ø6 scale 0.4→1, α 0→1; штрих α 1; эхо как у наведения", "focus_entered / focus_exited"),
	("Нажатие", "80 мс", "linear", "текст → soul, сдвиг на 1 px вниз, эхо встаёт на место (0,0)", "button_down / button_up"),
	("«Сохранено» на кнопке", "1.5 с", "—", "подпись → PAUSE_SAVED, цвет soul, иконка save.svg прорисовывается 600 мс, затем возврат", "SAVED_HINT_SECONDS (есть), таймер process_always"),
	("Раскрытие списка", "120 мс", "ease-out", "PopupMenu α 0→1, шеврон поворот 180° за 140 мс", "OptionButton.pressed + Tween"),
	("Ожидание клавиши", "1 с цикл", "steps(1)", "«_» в скобках и точка мигают", "Tween loop на modulate.a (0/1)"),
	("Обмен клавиш", "1.2 с", "ease-out", "обе клавиши вспыхивают over → soul_key, строка-сообщение снизу", "Tween на modulate"),
	("Открытие навыка", "1.0 с ×2", "ease-out", "кольцо от узла: scale 0.5→2.4, α 0.85→0; синапс от родителя прорисовывается 600 мс; имя и счётчик вспыхивают 1.2 с; строка «Ранг N открыт» 1.4 с", "Tween; кольцо — TextureRect со штрих-SVG"),
	("Возрождение", "1.4 с цикл", "ease-in-out", "рваный штрих под кнопкой бежит (dashoffset 1→0→−1), кнопка недоступна", "до сигнала RunManager о готовности слоя"),
	("Итоги → игра", "300 мс", "ease-in", "затемнение до bg_void, затем вход игры", "Tween на ColorRect"),
	("Портал на карте", "200 мс + 1.2 с", "ease-out", "смена слоя — кроссфейд; второй конец портала пульсирует", "Tween"),
	("Отметка игрока", "3.2 с цикл", "ease-in-out", "ореол дышит: scale .92↔1.08, α .7↔1 (как ag-breathe HUD)", "Tween loop"),
	("Главное меню: сцена", "6 с / 5.3 с цикл", "sine", "камера-душа покачивается ±4 см; лампа подмигивает (α .55 на 1 кадр); пылинки в луче", "AnimationPlayer в L_menu_map"),
]
ANIM_NOTE = "Все твины меню — на `Tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)` / таймеры с `process_always = true`: игра в этот момент на паузе (как уже сделано для «Сохранено»)."

SHADER = """shader_type canvas_item;
// Фон под паузой, навыками и картой в забеге: мир «заволакивает», как мысль.
// ColorRect на весь экран, CanvasLayer ниже меню и выше HUD.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 1.0) = 0.0;      // твин 0→1 за 220 мс
uniform float blur_lod : hint_range(0.0, 5.0) = 2.6;    // размытие через мип-уровень
uniform float desaturate : hint_range(0.0, 1.0) = 0.7;
uniform vec4 scrim : source_color = vec4(0.043, 0.039, 0.051, 0.66);  // bg_void α .66
uniform vec4 tint : source_color = vec4(0.071, 0.039, 0.118, 0.95);   // #120A1E
uniform float vig_inner : hint_range(0.0, 1.5) = 0.30;
uniform float vig_outer : hint_range(0.0, 1.5) = 1.00;

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, blur_lod * amount).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(l), desaturate * amount);
	c = mix(c, scrim.rgb, scrim.a * amount);
	vec2 d = (SCREEN_UV - 0.5) / vec2(0.72, 0.78);
	float v = smoothstep(vig_inner, vig_outer, length(d) * 2.0);
	c = mix(c, tint.rgb, v * tint.a * amount);
	COLOR = vec4(c, 1.0);
}"""
SHADER_NOTE = "Один ColorRect на весь экран в CanvasLayer между HUD (−1) и меню. Обводка интерактива и HUD-текст тоже заволакиваются — это правильно: на паузе их не читают."
SHADER_PARAMS = [
	("`amount`", "0 → 1 за 220 мс, обратно за 160", "одна ручка для входа/выхода"),
	("`blur_lod`", "2.6", "мир не отвлекает, но силуэты угадываются"),
	("`desaturate`", "0.70", "серость = остановленное время; сиреневое меню — единственный цвет"),
	("`scrim`", "#0B0A0D α 0.66", "контраст текста ≥ 7 : 1 над любым кадром"),
	("`tint, vig_inner, vig_outer`", "#120A1E α .95 · 0.30 · 1.00", "та же виньетка, что у распада души в HUD — меню «внутри головы»"),
]
SCENE_NOTES = [
	("Главное меню: живая сцена", "A: **операционная глазами души**. Камера под потолком (высота 2.6 м, наклон −24°) смотрит на каталку: тело под простынёй, рядом пустой бак, где держали мозг, — из него тянутся сиреневые струйки (GPUParticles3D, 6 частиц/с, жизнь 4 с, emission soul ×2). Единственный свет — лампа-конус 3200 K с подмигиванием раз в ~5 с; пыль в луче (GPUParticles3D, 120 частиц, медленный дрейф). Камера «дышит»: ±4 см по Y за 6 с. Меню стоит слева, композиция смещена вправо (точка схода x 1040). Кадр-набросок — в прототипе A. Сцена кладётся в существующий `src/levels/menu_map/L_menu_map.tscn`."),
	("Итоги: рассеяние", "GPUParticles2D поверх bg_void: 40 точек Ø 2–4 soul α .6, жизнь 6 с, скорость вверх 12–30 px/с, разлёт ±25°, альфа 0 → .8 → 0. Заголовок исхода — Label + два эха (soul α .30 со сдвигом (4, 1) и α .12 со сдвигом (10, −2), размытие у второго)."),
]

ECHO = """# res://src/ui/menu/echo_button.gd
## Кнопка-мысль языка «Отголосок». Тема даёт ей цвета, шрифт, отступы и
## запасной фокус-StyleBox; сама кнопка рисует то, что StyleBox не умеет:
## сиреневое эхо текста и рваный штрих, прорисовывающийся при наведении.
class_name UI_EchoButton
extends Button

const ECHO_COLOR := Color(0.79, 0.66, 0.95, 0.30)
const ECHO_PERIOD := 1.9
const RAG := PackedVector2Array([...])  # 15 точек штриха в долях ширины, см. rag_line.svg

var _hot := 0.0       # 0…1 — эхо и штрих (наведение или фокус)
var _t := 0.0

func _process(delta: float) -> void:
	var target := 1.0 if (is_hovered() or has_focus()) and not disabled else 0.0
	_hot = move_toward(_hot, target, delta / 0.14)
	_t += delta
	if _hot > 0.0:
		queue_redraw()

func _draw() -> void:
	if _hot <= 0.0:
		return
	var font := get_theme_font(&"font")
	var size := get_theme_font_size(&"font_size")
	var a := TAU * _t / ECHO_PERIOD
	var jitter := Vector2(2.0 + 0.8 * sin(a), 0.6 * sin(a * 2.0 + 1.0))
	var c := ECHO_COLOR
	c.a *= _hot
	draw_string(font, _text_origin() + jitter, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)
	_draw_rag(_hot)  # штрих под строкой до доли _hot ширины"""

TREES = [
	("Главное меню", """UI_MainMenu (Control, full rect)                 src/ui/main_menu/main_menu.tscn
├─ ThoughtShadow (TextureRect)                   x 0…760, радиальный #060509 α .86→0, центр (14 %, 52 %)
├─ Title (Label, variation Title, uppercase)      x 112, y 156 — MENU_TITLE
│  └─ Echo (Label, modulate soul α .30, +2,0)
├─ Items (VBoxContainer, separation 6)            x 82, y 318 — кнопки растут по тексту
│  ├─ NewGame (UI_EchoButton)    MENU_NEW_GAME
│  ├─ Load (UI_EchoButton)       MENU_LOAD + Aside(Label Caption) MENU_LOAD_EMPTY, disabled без сейва
│  ├─ Settings (UI_EchoButton)   MENU_SETTINGS
│  └─ Quit (UI_EchoButton)       MENU_QUIT
└─ Version (Label, Small, α .55)                 правый нижний угол, отступ 24/18 — MENU_BUILD % версия
За меню — 3D-сцена src/levels/menu_map/L_menu_map.tscn (уже грузится как фон меню)."""),
	("Пауза", """UI_PauseMenu (Control)                         src/ui/pause_menu/pause_menu.tscn
├─ Backdrop (ColorRect + menu_backdrop.gdshader) — §8, вместо Panel
├─ ThoughtShadow (TextureRect 600×420, центр экрана)
└─ Column (VBoxContainer, separation 4, по центру, y 200)
   ├─ Whisper (Label) PAUSE_TITLE, нижний отступ 22
   ├─ Continue (UI_EchoButton)  PAUSE_CONTINUE
   ├─ Save (UI_EchoButton)      PAUSE_SAVE → PAUSE_SAVED / PAUSE_SAVE_NOTHING на 1.5 с, + иконка save.svg
   ├─ Settings (UI_EchoButton)  MENU_SETTINGS
   └─ ToMenu (UI_EchoButton)    PAUSE_TO_MENU"""),
	("Настройки", """UI_SettingsMenu (Control)                       src/ui/settings_menu/settings_menu.tscn
├─ Whisper SETTINGS_TITLE                       x 112, y 52
├─ Back (KeyHint [Esc] HINT_BACK)               справа 40, сверху 36 — = «Отмена»
├─ Tabs (TabContainer, tabs_position top)       вкладки x 86, y 80, h_separation 18
│  ├─ SETTINGS_TAB_GRAPHICS  — Rows (VBox, x 112, y 150, ширина 880; строка 46)
│  │    Пресет (OptionButton) · Масштаб (HSlider 50–100 %, шаг 5) · Тени (CheckBox)
│  │    Разрешение теней (OptionButton, disabled при выкл. тенях) · Сглаживание (OptionButton)
│  │    Вертикальная синхронизация (CheckBox) · Поле зрения (HSlider 60–110°) · Ограничение FPS (HSlider 0–240, 0 = SETTINGS_FPS_UNLIMITED)
│  ├─ SETTINGS_TAB_AUDIO     — Общая громкость (HSlider 0–100 %)
│  └─ SETTINGS_TAB_CONTROLS  — Чувствительность мыши (HSlider 0.1–5.0) + SETTINGS_KEYS:
│       GridContainer 2 колонки (зазор 56), строка 40: UI_KeyRow = подпись + KeyHint [ W ]
├─ Hint (VBox x 1060, y 162, ширина 330)        название строки + SETTINGS_HINT_* наведённой/в фокусе строки
└─ Footer (HBox, справа 96, снизу 40, separation 22)
   SETTINGS_DIRTY (Caption, только при изменениях) · Cancel · Reset · Apply (disabled без изменений)"""),
	("Итоги забега", """UI_DeathScreen (Control)                        src/ui/death_screen/death_screen.tscn
├─ Void (ColorRect bg_void + радиальный #17131f сверху) + Fragments (GPUParticles2D: 40 точек soul, жизнь 6 с, вверх 12–30 px/с)
└─ Column (VBox по центру, y 96)
   ├─ Whisper RUN_SUMMARY_HEADING
   ├─ Title (DeathTitle) RUN_SUMMARY_TITLE_DEATH | _EVAC | _FINAL — исход приходит параметром
   ├─ Subtitle (Body, ширина ≤ 640, autowrap) RUN_SUMMARY_SUBTITLE_*
   ├─ Stats (VBox ширина 560, строка 34; отступ сверху 34) — строится из data/run_stat_catalog.tres:
   │    HBox: Label(Caption) · Leader (TextureRect, пунктир 1:3, expand) · Label(Value, справа, ≤ 300, autowrap)
   └─ Revive (UI_EchoButton, отступ сверху 34) RUN_SUMMARY_REVIVE → RUN_SUMMARY_REVIVING (disabled) + Loader"""),
	("Навыки и улучшения Архитектора", """UI_SkillTree (Control)                          src/ui/skill_tree/skill_tree_ui.tscn
├─ Backdrop (§8)
├─ Whisper SKILL_TITLE (x 112, y 52) · Tabs SKILL_TAB_SOUL / SKILL_TAB_ARCHITECT (x 86, y 80)
├─ Wallet (VBox x 740, y 70): Caption SKILL_POINTS | ARCHITECT_ESSENCE + Value 40/600 (+ Toast SKILL_UNLOCKED)
├─ Net (Control 80…1000 × 120…700) — skill_graph_view: координаты узлов — данные раскладки (graph_row уже есть)
│  ├─ Links (Line2D на связь: рваная полилиния, амплитуда 3.2 px; горит soul 1.8 px / доступна text α .45 / закрыта пунктир 1:3)
│  ├─ Nodes (UI_SkillNeuron: Button 44×44; ядро Ø14, кольцо рангов r 17 сегментами с зазором 16°)
│  └─ Labels (имя 15/500 + «r/max» 12) справа или слева от узла, 26 px от центра
│  Архитектор: тот же граф поверх знака комплекса (знак ×2.2, штрих 14 px, text α .07); ветви мира — концы знака
└─ Card (VBox x 1060, y 150, ширина 340): ветвь · имя (26/600 + эхо) · ранги (точки Ø7) + SKILL_RANK ·
   описание · SKILL_COST · SKILL_REQUIRES + список · кнопка SKILL_UNLOCK / NO_POINTS / NO_ESSENCE / LOCKED / MAXED"""),
	("Карта комплекса", """UI_ComplexMap (Control)                         src/ui/map/complex_map_screen.tscn
├─ Backdrop (§8) · Whisper MAP_TITLE (x 112, y 52) · Close (KeyHint [Esc] MAP_CLOSE, справа 40, сверху 36)
├─ Slice (VBox x 112, y 110, ширина 364) — вместо списка слоёв: «срез» комплекса
│  └─ UI_MapStratum ×6 (Button, высота 86 + 4): «L0» 15/600 + MAP_LAYER_SURFACE/DEPTH;
│     этажи — тонкие линии, комнаты — штрихи 3 px (посещённые soul α .75, прочие text α .4);
│     неизвестный слой — штриховка −28° и MAP_LAYER_CLOSED; отметка игрока — точка с ореолом
│     порталы между слоями — вертикальный пунктир soul 2:3 через границу слоёв
├─ Plans (Control x 560, y 110, 840×490) — этажи выбранного слоя сеткой (колонки подбираются под крупную клетку,
│  клетка ≤ 34 px): MAP_FLOOR над планом; комнаты Button (посещённая: рамка text α .75 + заливка soul α .10;
│  неисследованная: пунктир; лестница: вертикальная штриховка; уникальная — подпись 11/600 soul_key на уровне 4);
│  коридоры 2.4 px text α .5 (неизвестные — пунктир 3:4 α .2); порталы — кольцо Ø22 soul со стрелкой
├─ Info (Label x 560, y 620, ширина 840) — описание наведённой комнаты или MAP_HINT
└─ Level (Caption x 112, y 660) MAP_LEVEL; уровень 0 — по центру MAP_NO_LINK с эхом"""),
]

TRANSLATION = [
	"Весь видимый текст — ключом: в `.tscn` у Label/Button в `text` лежит ключ, `auto_translate_mode` включён; в коде — `tr(\"KEY\")`. Данные (`.tres`) хранят ключ, не готовую строку.",
	"Подстановки — `tr(\"MAP_LEVEL\") % [level, max]`. Имена клавиш — значения из `SettingsManager.code_display_name()`; локализуются только «Пробел», ЛКМ/ПКМ/СКМ (KEY_*).",
	"Регистр — свойством узла (`uppercase`), не в строке: в CSV `RUN_SUMMARY_TITLE_DEATH` предлагается в обычном регистре, капс даёт Label.",
	"Русское множественное число не нужно: везде схема «подпись — число» («Очки навыков 3», «Эссенция 12,4 тыс.»). Если понадобится — по образцу ARCHITECT_ESSENCE_ONE/FEW/MANY.",
	"Тысячи — `SKILL_THOUSANDS`: RU «12,4 тыс.» (запятая), EN «12.4k».",
	"Длинный английский проверен макетами: «Quit to main menu», «Vertical synchronization», «Reset to defaults», «Not enough points», «Meet the requirements first». Кнопки — по тексту, подписи строк переносятся в колонке 340, значения — по тексту.",
]

CODE_CHANGES = [
	("`assets/ui/menu_theme.tres`", "новая тема по §5 (текстовая .tres, а не бинарная); подключить в project.godot → gui/theme/custom"),
	("`assets/fonts/`", "GolosText-VariableFont_wght.ttf + FontVariation на 400/500/600"),
	("`assets/ui/menu/*.svg`", "иконки и текстуры §6"),
	("`src/ui/menu/echo_button.gd`", "UI_EchoButton (эхо, штрих), UI_KeyRow, UI_SettingRow — по §5"),
	("`src/ui/menu/menu_backdrop.gdshader`", "§8; заменить Panel-подложки паузы, навыков и карты"),
	("`src/ui/main_menu/main_menu.tscn/.gd`", "раскладка §9; `version_label.text = tr(\"MENU_BUILD\") % version` вместо «v%s»"),
	("`src/ui/pause_menu/pause_menu.gd`", "«Сохранено»/«Сохранять нечего» — ключи PAUSE_SAVED / PAUSE_SAVE_NOTHING; добавить иконку save.svg на время отметки"),
	("`src/ui/settings/keybinds_setting.gd`", "CAPTURE_HINT → SETTINGS_REBIND_WAIT; показывать SETTINGS_REBIND_SWAPPED при обмене"),
	("`src/ui/settings/graphics_preset_setting.gd, aa_mode_setting.gd`", "CUSTOM_LABEL и пункты «Выкл/FXAA/MSAA» → ключи SETTINGS_PRESET_CUSTOM, SETTINGS_AA_OFF; display_name в data/graphics_presets.tres → SETTINGS_PRESET_*"),
	("`src/autoloads/settings_manager.gd`", "REBINDABLE_ACTIONS: значения → ACTION_*; MOUSE_BUTTON_NAMES → KEY_LMB/RMB/MMB"),
	("`src/ui/settings_menu/settings_menu.tscn`", "подписи строк → SETTINGS_*; tooltip «0 — без ограничения» → SETTINGS_HINT_FPS в колонку подсказки"),
	("`data/skill_tree.tres`", "display_name / description навыков и ветвей → SKILL_*_NAME / _DESC / SKILL_BRANCH_*"),
	("`src/ui/skill_tree/*`", "граф-нейросеть §9: Line2D-синапсы, UI_SkillNeuron, карточка; вкладка «Архитектор» поверх знака"),
	("`src/ui/map/complex_map_screen.tscn/.gd`", "список слоёв → срез (UI_MapStratum), этажи — сеткой; MAP_HINT без «Закрыть» (теперь [Esc] сверху)"),
	("`src/ui/death_screen/*`", "рассеяние, эхо заголовка, лоадер-штрих; исход — параметр (DEATH / EVAC / FINAL)"),
	("`dev/settings_menu_check, skill_graph_check, complex_map_check`", "обновить под новые узлы — headless-проверки через навык gameplay-testing"),
]

TOC = [("p1", "Принципы"), ("p2", "Палитра"), ("p3", "Шрифт и кегли"), ("p4", "Сетка, отступы, размеры"), ("p5", "Контролы: состояния и тема"),
	("p6", "Иконки"), ("p7", "Анимации и переходы"), ("p8", "Шейдеры"), ("p9", "Экраны: дерево узлов и раскладка"), ("p10", "Перевод: правила"),
	("p11", "Строки и ключи перевода"), ("p12", "Что поменять в коде")]


def palette_rows():
	for tok, hexc, a, where in PALETTE:
		eff = blend(hexc, BG, a) if a is not None else hexc
		cr = "—" if tok in NO_CONTRAST else "%.1f : 1" % contrast(eff, BG)
		yield tok, hexc + ("" if a is None else " α %.2f" % a), gcol(hexc, a), cr, where, eff


def csvq(s):
	return '"%s"' % s.replace('"', '""') if any(c in s for c in ',"\n') else s


def strings_csv(S):
	return "keys,ru,en\n" + "\n".join("%s,%s,%s" % (k, csvq(ru), csvq(en)) for k, ru, en, _ in S)


# ---------------------------------------------------------------- markdown

def md_cell(s):
	return str(s).replace("|", "\\|").replace("\n", " ")


def md_table(head, rows):
	out = ["| " + " | ".join(head) + " |", "|" + "|".join("---" for _ in head) + "|"]
	out += ["| " + " | ".join(md_cell(c) for c in r) + " |" for r in rows]
	return "\n".join(out)


def build_md(S):
	o = ["# Меню — спека переноса в Godot", "",
		"Карточка-спека к [[UI — переверстка меню]]. Язык **A «Отголосок»** (утверждён 01.10). "
		"Холст Claude Design с двумя прототипами, макетами состояний и HTML-версией этой спеки: %s "
		"(страницы «Прототипы», «Макеты A · Отголосок», «Макеты B · Терминал», «Спека (A)»); его копия и генератор — "
		"`design/menu/` в корне репозитория. Файл собран генератором (`design/menu/gen/spec.py`) — правки вносить там." % CANVAS_URL, ""]
	o += INTRO[:1] + [""] + INTRO[1:] + [""]
	n = 0

	def sec(title):
		nonlocal n
		n += 1
		o.extend(["## %d. %s" % (n, title), ""])

	sec("Принципы")
	o += ["- " + x for x in PRINCIPLES] + [""]
	sec("Палитра")
	o += [md_table(["Токен", "Hex", "Godot", "Контраст к bg_void", "Где"],
		[("`%s`" % t, "`%s`" % h, "`%s`" % g, c, w) for t, h, g, c, w, _ in palette_rows()]), "", PALETTE_NOTE, ""]
	sec("Шрифт и кегли")
	for x in FONT_NOTES:
		o += [x, ""]
	o += [md_table(["Роль", "Вариация темы", "Кегль", "Начертание", "Трекинг", "Интерлиньяж", "Регистр", "Цвет"],
		[(a, "`%s`" % b, c + " px", d, f, g + " px", h, i) for a, b, c, d, f, g, h, i in TYPE]), ""]
	sec("Сетка, отступы, размеры")
	o += [md_table(["Что", "Значение (px базового окна)"], GRID), ""]
	sec("Контролы: состояния и тема")
	o += [THEME_INTRO, "",
		"Матрица состояний (обычное · наведение · фокус с клавиатуры · нажато · недоступно; у перепривязки — ожидание клавиши) нарисована живыми образцами на странице «Спека (A)» холста и разложена по экранам на странице «Макеты A».", ""]
	for title, rows in THEME:
		o += ["### " + title, "", md_table(["Элемент темы", "Значение"], rows), ""]
		if title.startswith("Button"):
			o += ["```gdscript", ECHO, "```", ""]
	sec("Иконки")
	o += [ICONS_NOTE, "", md_table(["Файл", "Что", "Путь (viewBox 24, штрих 1.6)"],
		[("`%s`" % f, w, "`%s`" % d if d else ("путь знака — `design/menu/gen/scenes.py` LOGO_D" if d is None else "—")) for f, d, w in ICONS]), ""]
	sec("Анимации и переходы")
	o += [md_table(["Событие", "Длительность", "Кривая", "Что меняется", "Godot"], ANIM), "", ANIM_NOTE, ""]
	sec("Шейдеры")
	o += ["### menu_backdrop.gdshader — фон меню в забеге", "", SHADER_NOTE, "", "```glsl", SHADER, "```", "",
		md_table(["Параметр", "Значение", "Зачем"], SHADER_PARAMS), ""]
	for t, x in SCENE_NOTES:
		o += ["### " + t, "", x, ""]
	sec("Экраны: дерево узлов и раскладка")
	for t, tree in TREES:
		o += ["### " + t, "", "```text", tree, "```", ""]
	sec("Перевод: правила")
	o += ["- " + x for x in TRANSLATION] + [""]
	sec("Строки и ключи перевода")
	o += ["Все %d строк меню. «есть» — ключ уже в `assets/locale/ui.csv`; остальные — новые. Заголовок CSV тот же: `keys,ru,en`." % len(S), "",
		md_table(["Ключ", "ru", "en", "Где / примечание"], [("`%s`" % k, ru, en, note) for k, ru, en, note in S]), "",
		"### Готовый CSV", "", "```csv", strings_csv(S), "```", ""]
	sec("Что поменять в коде")
	o += [md_table(["Файл", "Что"], CODE_CHANGES), ""]
	o += ["## Связано", "",
		"- [[UI — переверстка меню]] — решения и промпт.",
		"- [[HUD — спека]] — язык «Отголосок» в HUD: токены, эхо, смятение T.",
		"- [[Локализация — миграция текстов]] — ключи перевода.",
		"- [[Конвенции проекта]] §3–§4 — тема UI, иконки, перевод.", ""]
	return "\n".join(o)


# ---------------------------------------------------------------- html (страница холста)

TH = 'style="text-align:left;font-weight:600;color:#E6E1EC;padding:8px 12px;border-bottom:1px solid #3a3440;font-size:13px;white-space:nowrap"'
TD = 'style="padding:8px 12px;border-bottom:1px solid #221d28;vertical-align:top;font-size:14px;line-height:20px"'
CODE_STYLE = 'style="font-family:\'IBM Plex Mono\',monospace;font-size:13px;color:#E9DDFF;background:#1a171e;padding:1px 5px;border-radius:3px"'


def inl(s):
	"""Строчная разметка markdown → HTML: `код`, **жирный**, *курсив*."""
	parts = re.split(r"(`[^`]+`)", str(s))
	out = []
	for p_ in parts:
		if p_.startswith("`") and p_.endswith("`") and len(p_) > 1:
			out.append("<code %s>%s</code>" % (CODE_STYLE, e(p_[1:-1])))
		else:
			x = e(p_)
			x = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", x)
			x = re.sub(r"\*(.+?)\*", r"<i>\1</i>", x)
			out.append(x)
	return "".join(out)


def table(head, rows):
	out = ['<div style="overflow-x:auto;margin:14px 0 6px"><table style="width:100%;border-collapse:collapse;min-width:640px">']
	out.append("<tr>" + "".join("<th %s>%s</th>" % (TH, h) for h in head) + "</tr>")
	for r in rows:
		out.append("<tr>" + "".join("<td %s>%s</td>" % (TD, c) for c in r) + "</tr>")
	out.append("</table></div>")
	return "".join(out)


def pre(s):
	return '<pre style="margin:12px 0;padding:16px 18px;background:#0c0b0e;border:1px solid #2a2530;border-radius:6px;overflow-x:auto;font:13px/19px \'IBM Plex Mono\',monospace;color:#E6E1EC;white-space:pre">%s</pre>' % e(s)


def h2(id_, n, t):
	return '<h2 id="%s" style="margin:64px 0 6px;font-size:26px;line-height:32px;font-weight:600;color:#F1E8FF">%d. %s</h2>' % (id_, n, t)


def h3(t):
	return '<h3 style="margin:30px 0 4px;font-size:18px;font-weight:600;color:#E6E1EC">%s</h3>' % e(t)


def p(t):
	return '<p style="margin:10px 0;font-size:15px;line-height:23px;color:#C9C2D3;max-width:900px">%s</p>' % inl(t)


def li(items):
	return '<ul style="margin:10px 0;padding-left:22px;max-width:920px">' + "".join('<li style="margin:6px 0;font-size:15px;line-height:23px;color:#C9C2D3">%s</li>' % inl(i) for i in items) + "</ul>"


RAG = ('<svg class="ag-rag" viewBox="0 0 100 6" preserveAspectRatio="none" aria-hidden="true"><path pathLength="1" vector-effect="non-scaling-stroke" '
	'd="M0 3.2 L6 2.4 L12 3.6 L19 2.9 L27 3.8 L34 2.6 L41 3.3 L49 2.2 L57 3.5 L64 2.8 L72 3.9 L80 2.7 L87 3.4 L94 2.5 L100 3.1"></path></svg>')


def sample(cls_extra, text, small=False, disabled=False):
	return '<button class="ag-item%s%s" data-text="%s"%s>%s%s</button>' % (" sm" if small else "", cls_extra, e(text), " disabled" if disabled else "", e(text), RAG)


def states_matrix():
	cols = ["обычное", "наведение", "фокус с клавиатуры", "нажато", "недоступно"]
	mods = ["", " is-hover", " is-focus", " is-press", ""]
	cell = 'style="padding:14px 10px;border-bottom:1px solid #221d28;vertical-align:middle"'
	lab = '<td %s><span style="color:#B4ADC0;font-size:13px">%s</span></td>'
	out = ['<div style="overflow-x:auto;margin:16px 0;background:#0B0A0D;border:1px solid #2a2530;border-radius:6px;padding:8px 8px 4px"><table class="ag" style="border-collapse:collapse;width:100%;min-width:1060px">']
	out.append("<tr><th %s></th>" % TH + "".join("<th %s>%s</th>" % (TH, c) for c in cols) + "</tr>")
	row = [lab % (cell, "Кнопка-мысль<br>EchoButton")]
	for i, m in enumerate(mods):
		row.append("<td %s>%s</td>" % (cell, sample(m, "Новая игра", False, i == 4)))
	out.append("<tr>" + "".join(row) + "</tr>")
	row = [lab % (cell, "Малая<br>EchoButtonSmall")]
	for i, m in enumerate(mods):
		row.append("<td %s>%s</td>" % (cell, sample(m, "Применить", True, i == 4)))
	out.append("<tr>" + "".join(row) + "</tr>")
	row = [lab % (cell, "Вкладка<br>TabBar")]
	for i, m in enumerate(["", " is-hover", " is-focus is-sel", " is-press", ""]):
		extra = ' style="opacity:.35;cursor:default"' if i == 4 else ""
		row.append('<td %s><button class="ag-tab%s" data-text="Графика"%s>Графика%s</button>%s</td>' % (cell, m, extra, RAG, '<div class="ag-caption" style="font-size:11px;margin-left:26px">выбрана: is-sel</div>' if i == 2 else ""))
	out.append("<tr>" + "".join(row) + "</tr>")
	row = [lab % (cell, "Слайдер<br>HSlider")]
	bg = "linear-gradient(to right, #C9A8F2 0 60%, transparent 60%), repeating-linear-gradient(to right, rgba(236,232,242,.34) 0 1px, transparent 1px 4px)"
	for i, m in enumerate(["", " is-hover", " is-focus", " is-press", ""]):
		row.append('<td %s><div class="ag-row%s" style="display:block;min-height:0"><input type="range" class="ag-range" min="0" max="100" value="60" style="width:150px;background-image:%s"%s aria-label="Поле зрения"></div></td>' % (cell, m, bg, " disabled" if i == 4 else ""))
	out.append("<tr>" + "".join(row) + "</tr>")
	row = [lab % (cell, "Флажок<br>CheckBox")]
	for i, m in enumerate(["", " is-hover", " is-focus", " is-press", ""]):
		on = i in (1, 2, 3)
		row.append('<td %s><div class="ag-row%s" style="display:block;min-height:0"><button class="ag-check%s"%s><span class="ag-box">%s</span><span>%s</span></button></div></td>' % (
			cell, m, "" if on else " is-off", ' style="opacity:.35"' if i == 4 else "", '<span class="ag-tick"></span>' if on else "", "Вкл" if on else "Выкл"))
	out.append("<tr>" + "".join(row) + "</tr>")
	chev = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M6 9l6 6 6-6"></path></svg>'
	row = [lab % (cell, "Список<br>OptionButton")]
	for i, m in enumerate(["", " is-hover", " is-focus", " is-press", ""]):
		row.append('<td %s><div class="ag-row%s" style="display:block;min-height:0"><button class="ag-drop%s"%s><span>MSAA 2×</span>%s%s</button></div></td>' % (cell, m, m if i == 1 else (" is-open" if i == 3 else ""), " disabled" if i == 4 else "", chev, RAG))
	out.append("<tr>" + "".join(row) + "</tr>")
	row = [lab % (cell, "Клавиша<br>UI_KeyRow")]
	kh = '<span class="ag-kh"><span class="br">[</span><span class="k">W</span><span class="br">]</span></span>'
	for i, m in enumerate(["", " is-hover", " is-focus", " is-press", " is-wait"]):
		inner = kh if i != 4 else '<span class="ag-kh"><span class="ag-wait">нажмите клавишу</span><span class="br">[</span><span class="k ag-cursor">_</span><span class="br">]</span></span>'
		row.append('<td %s><button class="ag-key-row%s" style="width:200px"><span>Вперёд</span>%s</button>%s</td>' % (cell, m, inner, '<div class="ag-caption" style="font-size:11px;margin-left:24px">5-й столбец: ожидание клавиши</div>' if i == 4 else ""))
	out.append("<tr>" + "".join(row) + "</tr>")
	out.append("</table></div>")
	return "".join(out)


def icon_cells(logo_d):
	cells = []
	for name, d, what in ICONS:
		if d is None:
			svg = '<svg width="40" height="40" viewBox="0 0 250 250" fill="none" stroke="#C9A8F2" stroke-width="14" stroke-linecap="round" stroke-linejoin="round"><path d="%s"></path></svg>' % logo_d
		elif d:
			svg = '<svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="#C9A8F2" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="%s"></path></svg>' % d
		else:
			svg = {
				"focus_echo.svg": '<svg width="64" height="44" viewBox="0 0 64 44"><circle cx="13" cy="22" r="8" fill="#C9A8F2" opacity=".14"></circle><circle cx="13" cy="22" r="3" fill="#C9A8F2"></circle><path d="M30 39.2 L36 38.4 L42 39.6 L48 38.9 L54 39.8 L60 38.6" fill="none" stroke="#C9A8F2" stroke-width="1.2"></path></svg>',
				"slider_dot.svg": '<svg width="22" height="22" viewBox="0 0 22 22"><circle cx="11" cy="11" r="10.5" fill="#F2EEF7" opacity=".1"></circle><circle cx="11" cy="11" r="4.5" fill="#F2EEF7"></circle></svg>',
				"check_on.svg / check_off.svg": '<svg width="40" height="18" viewBox="0 0 40 18"><circle cx="9" cy="9" r="7.25" fill="none" stroke="#ECE8F2" stroke-width="1.5"></circle><circle cx="9" cy="9" r="3.5" fill="#C9A8F2"></circle><circle cx="31" cy="9" r="7.25" fill="none" stroke="#ECE8F2" stroke-opacity=".6" stroke-width="1.5"></circle></svg>',
				"track_dotted.svg": '<svg width="64" height="6" viewBox="0 0 64 6"><path d="M0 3H64" stroke="#ECE8F2" stroke-opacity=".5" stroke-width="2" stroke-dasharray="1 3"></path></svg>',
			}[name]
		cells.append('<div style="display:flex;align-items:center;gap:14px;padding:12px;border:1px solid #2a2530;border-radius:6px;background:#0B0A0D">%s<div><div style="font:13px \'IBM Plex Mono\',monospace;color:#E6E1EC">%s</div><div style="font-size:13px;color:#A49DB0">%s</div></div></div>' % (svg, e(name), e(what)))
	return '<div style="display:grid;grid-template-columns:repeat(3, minmax(0, 1fr));gap:12px;margin:14px 0">' + "".join(cells) + "</div>"


def build(STR, S, a_css, fonts, logo_d):
	b = []
	b.append('<div style="max-width:1180px;margin:0 auto;padding:56px 32px 120px;font-family:\'Golos Text\',sans-serif;color:#C9C2D3">')
	b.append('<div style="font:12px \'IBM Plex Mono\',monospace;color:#8f879b;letter-spacing:.06em">Astral Genesis · меню · спека переноса · сборка 0.7.0</div>')
	b.append('<h1 style="margin:10px 0 0;font-size:40px;line-height:48px;font-weight:600;color:#F1E8FF">Меню — язык A «Отголосок»</h1>')
	b += [p(x) for x in INTRO]
	b.append('<nav style="margin:26px 0 0;display:grid;grid-template-columns:repeat(3, minmax(0, 1fr));gap:4px 24px">' + "".join(
		'<a href="#%s" style="color:#C9A8F2;text-decoration:none;font-size:15px;line-height:26px">%d. %s</a>' % (i, n + 1, t) for n, (i, t) in enumerate(TOC)) + "</nav>")

	b.append(h2("p1", 1, "Принципы"))
	b.append(li(PRINCIPLES))
	b.append(h2("p2", 2, "Палитра"))
	rows = []
	for t, h, g, c, w, eff in palette_rows():
		sw = '<span style="display:inline-block;width:28px;height:18px;border-radius:3px;border:1px solid #3a3440;background:%s;vertical-align:middle"></span> ' % eff
		rows.append([sw + inl("`%s`" % t), inl("`%s`" % h), inl("`%s`" % g), c, e(w)])
	b.append(table(["Токен", "Hex", "Godot", "Контраст к bg_void", "Где"], rows))
	b.append(p(PALETTE_NOTE))
	b.append(h2("p3", 3, "Шрифт и кегли"))
	b += [p(x) for x in FONT_NOTES]
	b.append(table(["Роль", "Вариация темы", "Кегль", "Начертание", "Трекинг", "Интерлиньяж", "Регистр", "Цвет"],
		[[e(a), inl("`%s`" % bb), c + " px", d, f, g + " px", h, e(i)] for a, bb, c, d, f, g, h, i in TYPE]))
	b.append(h2("p4", 4, "Сетка, отступы, размеры"))
	b.append(table(["Что", "Значение (px базового окна)"], [[e(a), inl(c)] for a, c in GRID]))
	b.append(h2("p5", 5, "Контролы: состояния и тема"))
	b.append(p("Живые образцы — те же стили, что в прототипе A. " + THEME_INTRO))
	b.append(states_matrix())
	for title, rows in THEME:
		b.append(h3(title))
		b.append(table(["Элемент темы", "Значение"], [[inl(a), inl(c)] for a, c in rows]))
		if title.startswith("Button"):
			b.append(pre(ECHO))
	b.append(h2("p6", 6, "Иконки"))
	b.append(p(ICONS_NOTE))
	b.append(icon_cells(logo_d))
	b.append(h2("p7", 7, "Анимации и переходы"))
	b.append(table(["Событие", "Длительность", "Кривая", "Что меняется", "Godot"], [[e(x) for x in r] for r in ANIM]))
	b.append(p(ANIM_NOTE))
	b.append(h2("p8", 8, "Шейдеры"))
	b.append(h3("menu_backdrop.gdshader — фон меню в забеге"))
	b.append(p(SHADER_NOTE))
	b.append(pre(SHADER))
	b.append(table(["Параметр", "Значение", "Зачем"], [[inl(a), e(c), e(d)] for a, c, d in SHADER_PARAMS]))
	for t, x in SCENE_NOTES:
		b.append(h3(t))
		b.append(p(x))
	b.append(p("Для сравнения, B: пультовая — стена мониторов, один живой с заставкой знака и широкими серыми полосами помех."))
	b.append(h2("p9", 9, "Экраны: дерево узлов и раскладка"))
	for t, tree in TREES:
		b.append(h3(t))
		b.append(pre(tree))
	b.append(h2("p10", 10, "Перевод: правила"))
	b.append(li(TRANSLATION))
	b.append(h2("p11", 11, "Строки и ключи перевода"))
	b.append(p("Все %d строк меню. «есть» — ключ уже в `assets/locale/ui.csv`; остальные — новые. Заголовок CSV тот же: `keys,ru,en`." % len(S)))
	b.append(table(["Ключ", "ru", "en", "Где / примечание"],
		[[inl("`%s`" % k), e(ru), e(en), '<span style="color:#A49DB0;font-size:13px">%s</span>' % e(note)] for k, ru, en, note in S]))
	b.append(h3("Готовый CSV"))
	b.append(pre(strings_csv(S)))
	b.append(h2("p12", 12, "Что поменять в коде"))
	b.append(table(["Файл", "Что"], [[inl(a), inl(c)] for a, c in CODE_CHANGES]))
	b.append("</div>")

	return ('<!doctype html>\n<html lang="ru">\n<head>\n<meta charset="utf-8">\n<title>Спека меню для Godot</title>\n<script src="./support.js"></script>\n</head>\n<body>\n<x-dc>\n<helmet>\n%s\n<style>\n%s\nbody{background:#121015}\na:hover{color:#E9DDFF !important;text-decoration:underline !important}\n</style>\n</helmet>\n'
		'<div style="background:#121015;min-height:100vh">%s</div>\n</x-dc>\n'
		'<script type="text/x-dc" data-dc-script data-props=\'{"$preview":{"width":1280,"height":14000}}\'>\nclass Component extends DCLogic {\n  renderVals() { return {}; }\n}\n</script>\n</body>\n</html>\n') % (fonts, a_css, "".join(b))
