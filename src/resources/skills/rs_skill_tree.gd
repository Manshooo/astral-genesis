class_name RS_SkillTree
extends Resource

@export var skills: Array[RS_SkillDefinition] = []

func get_definition(id: StringName) -> RS_SkillDefinition:
	for skill in skills:
		if skill.id == id:
			return skill
	return null

func get_branch_skills(branch: StringName) -> Array[RS_SkillDefinition]:
	return skills.filter(func(s): return s.branch == branch)
