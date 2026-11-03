extends PhysicalBoneSimulator3D
##
## Соседние физические кости, связанные суставом, не сталкиваются друг с другом.
##
## Jolt этого сам не делает (проверено на 4.7.2): формы бедра и голени
## перекрываются у колена, и сустав заклинивает — колено не гнётся. Исключения
## столкновений живут только в физическом сервере и в сцене не сохраняются,
## поэтому их ставит этот скрипт при входе в дерево. Вешается на симулятор
## скриптом импорта collision_post_import.gd; рядом с ним и устанавливается.


func _ready() -> void:
	var skeleton := get_parent() as Skeleton3D
	if skeleton == null:
		return
	var by_bone := {}
	for child in get_children():
		if child is PhysicalBone3D:
			by_bone[skeleton.find_bone((child as PhysicalBone3D).bone_name)] = child
	for bone_id: int in by_bone:
		# Родитель по суставу — ближайшая кость выше по скелету, у которой есть
		# своё тело: между ними могут быть кости без тел (Spine → Chest).
		var parent := skeleton.get_bone_parent(bone_id)
		while parent >= 0 and not by_bone.has(parent):
			parent = skeleton.get_bone_parent(parent)
		if parent < 0:
			continue
		var child_body: PhysicalBone3D = by_bone[bone_id]
		var parent_body: PhysicalBone3D = by_bone[parent]
		child_body.add_collision_exception_with(parent_body)
		parent_body.add_collision_exception_with(child_body)
