class_name SimpleInteractable
extends StaticBody3D
## Obecný interaktivní objekt (tablet na stole, kýbl…).
## Akce se předává jako Callable, aby nebylo potřeba psát nový skript.

var prompt := ""
var action: Callable
## Volitelně: prompt podle situace (func(player) -> String); prázdný text = použije se prompt.
var prompt_fn: Callable


static func create(p_prompt: String, p_action: Callable, size: Vector3, pos: Vector3) -> SimpleInteractable:
	var s := SimpleInteractable.new()
	s.prompt = p_prompt
	s.action = p_action
	s.position = pos
	s.collision_layer = 1
	s.collision_mask = 0
	s.set_meta("interactable", s)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	s.add_child(cs)
	return s


func get_prompt(player) -> String:
	if prompt_fn.is_valid():
		var t: String = prompt_fn.call(player)
		if t != "":
			return t
	return prompt


func interact(player) -> void:
	if action.is_valid():
		action.call(player)
