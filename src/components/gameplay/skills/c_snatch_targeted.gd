class_name C_SnatchTargeted
extends Component
## Метка на ТЕЛЕ, на которое БФЖ смотрит прямо сейчас и которое в пределах
## C_BodySnatch.capture_range. Ставит и снимает S_SnatchTargetDetector каждый
## физкадр; читают прицел (crosshair.gd) и S_BodySnatch — чтобы не кастовать луч
## второй раз в момент нажатия.
##
## Отдельный компонент, а не C_Highlighted: тот означает «интерактив под
## крестиком» и тянет за собой обводку (O_OutlineVisual) и подсказку в HUD.
## Тело для захвата — не интерактив: оно на слое enemies и без C_Interactable.
