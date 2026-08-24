class_name SkillTreeUI
extends Control

@onready var points_label: Label = $Panel/MarginContainer/VBox/Header/PointsLabel
@onready var branches_container: VBoxContainer = $Panel/MarginContainer/VBox/ScrollContainer/BranchesContainer

var _skill_manager: SkillManager
var _tree_data: RS_SkillTree
var _rows: Dictionary = {}  ## StringName -> {rank_label, unlock_button}

## Цвет вспышки строки/искр при разблокировке — тёплый golden, не из темы:
## тема несёт форму контролов, а разовый эффект-реакция к ней не относится.
const _FLASH_COLOR := Color(1.6, 1.35, 0.7)
const _FLASH_DURATION := 0.5
const _SPARK_COUNT := 16
const _SPARK_LIFETIME := 0.5


func setup(skill_manager, tree_data: RS_SkillTree) -> void:
	_skill_manager = skill_manager
	_tree_data = tree_data
	_skill_manager.skill_unlocked.connect(_on_skill_unlocked)
	_build_tree()
	_refresh_all()


func _build_tree() -> void:
	for child in branches_container.get_children():
		child.queue_free()
	_rows.clear()

	var branches: Dictionary = {}  # StringName -> Array[RS_SkillDefinition]
	for def in _tree_data.skills:
		if not branches.has(def.branch):
			branches[def.branch] = []
		branches[def.branch].append(def)

	for branch_name in branches.keys():
		var branch_box := VBoxContainer.new()
		branch_box.add_theme_constant_override("separation", 6)

		var branch_label := Label.new()
		branch_label.text = str(branch_name).capitalize()
		branch_box.add_child(branch_label)

		for def in branches[branch_name]:
			branch_box.add_child(_create_skill_row(def))

		branches_container.add_child(branch_box)


func _create_skill_row(def: RS_SkillDefinition) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var name_label := Label.new()
	name_label.text = def.display_name
	name_label.custom_minimum_size = Vector2(150, 0)
	name_label.tooltip_text = def.description
	row.add_child(name_label)

	var rank_label := Label.new()
	rank_label.custom_minimum_size = Vector2(80, 0)
	row.add_child(rank_label)

	var unlock_button := Button.new()
	unlock_button.custom_minimum_size = Vector2(140, 0)
	unlock_button.pressed.connect(_on_unlock_pressed.bind(def.id))
	row.add_child(unlock_button)

	_rows[def.id] = {"rank_label": rank_label, "unlock_button": unlock_button}
	return row


func _on_unlock_pressed(id: StringName) -> void:
	_skill_manager.unlock(id)


func _on_skill_unlocked(id: StringName, _new_rank: int) -> void:
	_refresh_all()
	_play_unlock_effect(id)


## Единственный источник эффекта — сигнал skill_unlocked (id, ранг), поэтому
## реакция не знает ни числа скиллов в дереве, ни того, откуда взялись очки:
## дерево и способы их заработка растут отдельной задачей, этот код их не
## трогает и не ломается от их изменений.
func _play_unlock_effect(id: StringName) -> void:
	var row_refs = _rows.get(id)
	if row_refs == null:
		return
	var unlock_button: Button = row_refs["unlock_button"]
	var row := unlock_button.get_parent() as Control
	if row == null:
		return

	_flash_row(row)
	_spawn_sparks(unlock_button)


func _flash_row(row: Control) -> void:
	row.modulate = _FLASH_COLOR
	var tween := create_tween()
	tween.tween_property(row, "modulate", Color.WHITE, _FLASH_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _spawn_sparks(anchor: Control) -> void:
	var particles := CPUParticles2D.new()
	anchor.add_child(particles)
	particles.position = anchor.size / 2.0
	particles.z_index = 10
	particles.one_shot = true
	particles.amount = _SPARK_COUNT
	particles.lifetime = _SPARK_LIFETIME
	particles.explosiveness = 1.0
	particles.direction = Vector2.UP
	particles.spread = 180.0
	particles.initial_velocity_min = 60.0
	particles.initial_velocity_max = 140.0
	particles.gravity = Vector2(0.0, 220.0)
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 4.0
	particles.color = Color(1.0, 0.85, 0.4)
	particles.emitting = true

	get_tree().create_timer(_SPARK_LIFETIME).timeout.connect(particles.queue_free)


func _refresh_all() -> void:
	points_label.text = "Очки: %d" % _skill_manager.save.skill_points
	for def in _tree_data.skills:
		_refresh_row(def)


func _refresh_row(def: RS_SkillDefinition) -> void:
	var row_refs = _rows.get(def.id)
	if row_refs == null:
		return
	var rank := _skill_manager.get_rank(def.id)
	var rank_label: Label = row_refs["rank_label"]
	var unlock_button: Button = row_refs["unlock_button"]

	rank_label.text = "Ранг: %d/%d" % [rank, def.max_rank]

	if rank >= def.max_rank:
		unlock_button.text = "Максимум"
		unlock_button.disabled = true
	else:
		var cost := def.cost_for_next_rank(rank)
		unlock_button.text = "Прокачать (%d)" % cost
		unlock_button.disabled = not _skill_manager.can_unlock(def.id)

func _on_close_pressed() -> void:
	UIManager.close_top()

func _exit_tree() -> void:
	if _skill_manager and _skill_manager.skill_unlocked.is_connected(_on_skill_unlocked):
		_skill_manager.skill_unlocked.disconnect(_on_skill_unlocked)
