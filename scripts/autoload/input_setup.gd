extends Node
## Registruje herní akce do InputMapu. Pokud akce už existuje
## (např. byla přenastavena v Project Settings), ponechá ji beze změny.


func _enter_tree() -> void:
	_key("move_forward", KEY_W)
	_key("move_back", KEY_S)
	_key("move_left", KEY_A)
	_key("move_right", KEY_D)
	_key("sprint", KEY_SHIFT)
	_key("jump", KEY_SPACE)
	_key("interact", KEY_E)
	_key("spray", KEY_F)
	_key("next_chem", KEY_Q)
	_key("place_item", KEY_B)
	_key("robot", KEY_G)
	_key("find_tools", KEY_R)
	_key("tablet", KEY_TAB)
	_key("talents", KEY_T)
	_key("pause", KEY_ESCAPE)
	_key("quick_save", KEY_F5)
	_key("quick_load", KEY_F9)
	_mouse("use_tool", MOUSE_BUTTON_LEFT)
	_mouse("alt_tool", MOUSE_BUTTON_RIGHT)
	_mouse("next_item", MOUSE_BUTTON_WHEEL_DOWN)
	_mouse("prev_item", MOUSE_BUTTON_WHEEL_UP)


func _ensure(action: String) -> bool:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	return InputMap.action_get_events(action).is_empty()


func _key(action: String, keycode: Key) -> void:
	if _ensure(action):
		var ev := InputEventKey.new()
		ev.physical_keycode = keycode
		InputMap.action_add_event(action, ev)


func _mouse(action: String, button: MouseButton) -> void:
	if _ensure(action):
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		InputMap.action_add_event(action, ev)
