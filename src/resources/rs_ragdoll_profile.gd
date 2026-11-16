# res://src/resources/rs_ragdoll_profile.gd
# Как оседает рэгдолл трупа: мягкие пределы суставов, слабая тяга к нейтральной позе, разлёт конечностей от удара.
# Один профиль на скелет (data/ragdoll/), ссылка — в C_Ragdoll сцены тела; работает S_Ragdoll. Вики: [[Захват тела]].
class_name RS_RagdollProfile
extends Resource

@export_group("Нейтральная поза")
## Нейтральная поза: кость → поворот от позы покоя, градусы в осях кости (X — ось сгиба, Y — вдоль кости).
## Тянутся только перечисленные кости; остальные лишь демпфируются и мягко упираются в пределы.
@export var neutral_pose: Dictionary[StringName, Vector3] = {}
## Тяга к нейтральной позе, 1/с²: угловое ускорение сустава на радиан отклонения. Слабее веса конечности —
## поза проступает, пока тело падает, а лёжа решает пол.
@export var pose_stiffness := 6.0
## Демпфирование всех суставов, 1/с: гасит относительное вращение соседних костей, иначе рэгдолл болтается.
@export var pose_damping := 2.5

@export_group("Мягкие пределы")
## За сколько градусов до предела сустава начинается торможение (не больше половины диапазона).
@export_range(1.0, 60.0) var soft_zone_degrees := 15.0
## Возврат от предела, 1/с²: у самого предела — полная величина, на входе в зону — ноль.
@export var soft_stiffness := 120.0
## Торможение движения к пределу, 1/с: сустав замедляется у предела, а не бьётся в него.
@export var soft_damping := 25.0

@export_group("Время")
## Сколько секунд после старта рэгдолла работают мышцы: дальше тело лежит и засыпает, кадр его не стоит.
@export var active_seconds := 3.0
## За сколько секунд мышцы гаснут к концу active_seconds.
@export var fade_seconds := 1.0

@export_group("Гибель")
## Доля клипа death, после которой свежий труп подхватывает рэгдолл — со скоростью костей из клипа. Клип даёт
## начало падения, физика — конец: досмотренный до конца клип оставлял тело на коленях, а рэгдолл стартовал с места.
@export_range(0.1, 1.0) var death_handover := 0.5
## Предел унаследованной из клипа скорости кости, м/с: рывок на стыке ключей не должен швырять тело.
@export var max_launch_speed := 5.0

@export_group("Удар")
## Кости, которые удар отбрасывает НАЗАД — по направлению удара (руки).
@export var hit_back_bones: PackedStringArray = PackedStringArray(["LeftUpperArm", "RightUpperArm"])
## Кости, которые удар бросает ВПЕРЁД — навстречу ударившему (ноги).
@export var hit_forward_bones: PackedStringArray = PackedStringArray(["LeftUpperLeg", "RightUpperLeg"])
## Угловая скорость, которую удар добавляет каждой такой кости, рад/с.
@export var hit_spin := 6.0
## Разброс величины: ±доля от hit_spin.
@export_range(0.0, 1.0) var hit_spin_jitter := 0.4
## Разброс оси вращения, градусы: без него обе руки и обе ноги летят зеркально.
@export_range(0.0, 90.0) var hit_axis_jitter_degrees := 25.0


## Поворот кости [param bone] в нейтральной позе, в её локальных осях; IDENTITY — кость не тянется.
func neutral_of(bone: StringName) -> Basis:
	if not neutral_pose.has(bone):
		return Basis.IDENTITY
	var degrees: Vector3 = neutral_pose[bone]
	return Basis.from_euler(Vector3(deg_to_rad(degrees.x), deg_to_rad(degrees.y), deg_to_rad(degrees.z)))


## Ставит скелет в нейтральную позу от позы покоя — тело, лежащее с начала, оседает из неё, а не из T-позы.
## Звать ДО старта рэгдолла: кости встают в позу скелета в момент старта.
func pose_skeleton(skeleton: Skeleton3D) -> void:
	for bone_name: StringName in neutral_pose:
		var bone := skeleton.find_bone(bone_name)
		if bone >= 0:
			skeleton.set_bone_pose_rotation(bone,
				(skeleton.get_bone_rest(bone).basis * neutral_of(bone_name)).get_rotation_quaternion())
