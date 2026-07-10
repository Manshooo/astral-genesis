# Система интерактивности

Интерактивные объекты в игре строятся на связке трёх вещей: компонент-маркер,
физический слой для луча взаимодействия и метод `interact()` на entity.

## 1. Требования к entity

Entity, с которой должен взаимодействовать игрок, обязана:

1. **Иметь компонент `C_Interactable`** (в `component_resources` в инспекторе,
   либо через `define_components()`).
```gdscript
   @export var action_name: StringName = &"interact"
   @export var prompt_text: String
   @export var enabled: bool = true
```
   `enabled = false` временно отключает взаимодействие без удаления компонента.

2. **Реализовать метод `interact()`**. Он вызывается напрямую
   `S_InteractInput`:
```gdscript
   func interact() -> void:
       UIManager.open_skill_tree(SkillManager, preload("res://data/skill_tree.tres"))
```
   Если метода нет — сработает `assert` в `S_InteractInput.process()`.

3. **Иметь коллайдер на слое `interactives` (layer_4, маска-бит 8)**.
   Луч игрока (`InteractRay`, дочерний узел `Camera3D`) настроен на
   `collision_mask = 8`, то есть попадает только в объекты слоя `interactives`.
   Коллайдер может висеть на самой entity (`use_collision = true` у CSG-нод,
   как у `CSGBox3D`) либо на дочернем `StaticBody3D` (как у инкубатора —
   `Incubator/InteractBody`).

## 2. Как резолвится цель луча

`S_InteractionDetector` каждый кадр кастует луч из `interact_ray` игрока и
поднимается по дереву узлов вверх от коллайдера, пока не найдёт `Entity` с
`C_Interactable`:

```gdscript
func _resolve_interactable(collider: Object) -> Entity:
	var node := collider as Node
	while node:
		if node is Entity and node.has_component(C_Interactable):
			var c := node.get_component(C_Interactable) as C_Interactable
			return node if c.enabled else null
		node = node.get_parent()
	return null
```

Отсюда следствие: **коллайдер не обязан быть на самой Entity** — можно
повесить `StaticBody3D` с `CollisionShape3D` глубоко внутри импортированной
сцены (как в `hub.tscn`), лишь бы где-то выше по иерархии была нода-Entity с
`C_Interactable`.

## 3. Визуальный отклик (крестик + обводка)

Два независимых наблюдателя реагируют на компонент `C_Highlighted`,
который `S_InteractionDetector` вешает/снимает на цель:

- **Прицел (`UI_Crosshair`)** слушает мировые сигналы `component_added` /
  `component_removed` и увеличивается при появлении `C_Highlighted` —
  работает для любой Entity, без требований к типу узла.
- **Обводка (`O_OutlineVisual`, Observer)** применяет
  `material_overlay` на `GeometryInstance3D`. Она ищет:
  1. саму entity, если это `GeometryInstance3D` (сюда попадают и
     `MeshInstance3D`, и CSG-примитивы — `CSGBox3D`, `CSGMesh3D` и т.д.);
  2. иначе — дочерний узел с именем **строго** `"MeshInstance3D"`.

  **Важно:** если твоя интерактивная сцена — не `GeometryInstance3D` и меш
  лежит в дочернем узле с другим именем (не `"MeshInstance3D"`), обводка не
  появится. Либо переименуй узел, либо расширь `_find_geometry()` под свой
  случай (например, поиском первого `GeometryInstance3D` через
  `find_children("*", "GeometryInstance3D", true)`).

## 4. Чек-лист при добавлении нового интерактивного объекта

- [ ] Entity extends `Entity` (или сцена с рутом-Entity)
- [ ] `C_Interactable` в `component_resources`
- [ ] Реализован `interact()`
- [ ] Коллайдер (сам объект или дочерний `StaticBody3D`) на слое `interactives`
- [ ] Меш — либо сам `GeometryInstance3D`-based рут, либо дочерний узел с
      именем `MeshInstance3D` (иначе обводка не сработает — см. §3)

## 5. Возможные проблемы

Если меш "моргает", убедись, что `material_override` установлен. Всё из-за blend_mode, который пытается смешаться с чем-то по умолчанию.
Я хз. Если будет стоять хоть какой-то дефолтный материал, то моргать перестанет.
