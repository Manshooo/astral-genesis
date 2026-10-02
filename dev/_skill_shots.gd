extends Node
## Временный «фотограф» экрана навыков. Не коммитится. Сейвы подменяются
## заглушками и не пишутся: покупка не зовётся, отклик играется руками.

const OUT := "C:/Users/admin/AppData/Local/Temp/claude/C--Users-admin-Documents-Godot-Projects-astral-genesis/ff4b7ed6-d588-4ec9-b7f8-f865572c3dc4/scratchpad/shots/"
const MENU_MAP := "res://src/levels/menu_map/L_menu_map.tscn"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(OUT)
	var locale := OS.get_environment("SHOT_LOCALE")
	if locale != "":
		TranslationServer.set_locale(locale)
	var tag := locale if locale != "" else "ru"

	var soul_save := PlayerSkillSave.new()
	soul_save.skill_points = 3
	soul_save.ranks = {&"body_snatch": 1, &"lifespan": 2, &"decay_capacity": 1, &"steady_legs": 1}
	SkillManager.save = soul_save
	var arch_save := PlayerSkillSave.new()
	arch_save.skill_points = 1400
	arch_save.met = true
	ArchitectManager.save = arch_save

	var bg: Node = load(MENU_MAP).instantiate()
	add_child(bg)
	(bg.find_child("MainMenuUi", true, false) as Control).hide()
	UIManager.enabled = true
	await _wait(0.5)
	UIManager.open_skill_tree(SkillManager, SkillManager.SKILL_TREE)
	await _wait(1.0)
	await _shot("10_skills_%s" % tag)

	var screen := get_tree().root.find_child("SkillTreeUI", true, false) as SkillTreeUI
	var graph := screen.find_child("Graph", true, false) as UI_SkillGraph
	var focus_target := graph.neuron(&"overflow_control")
	if focus_target:
		focus_target.grab_focus()
	await _wait(0.4)
	await _shot("11_skills_focus_%s" % tag)

	soul_save.ranks[&"capture_precision"] = 1
	screen._on_skill_unlocked(&"capture_precision", 1)
	await _wait(0.35)
	await _shot("12_skills_unlock_%s" % tag)

	(screen.find_child("TabArchitect", true, false) as BaseButton).pressed.emit()
	await _wait(0.8)
	await _shot("13_architect_%s" % tag)
	UIManager.enabled = false
	UIManager.close_all()
	get_tree().quit()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + shot_name + ".png")
	print("shot ", shot_name)
