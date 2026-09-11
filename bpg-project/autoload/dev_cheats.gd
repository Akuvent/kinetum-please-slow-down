extends Node
## Hidden Konami unlock for local proto cheats (noclip, kinetum fill).
## Sequence: up up down down left right left right B A.
## Arrows or WASD both count for the directions.

#region Config
const SEQUENCE: Array[int] = [
	KEY_UP, KEY_UP, KEY_DOWN, KEY_DOWN,
	KEY_LEFT, KEY_RIGHT, KEY_LEFT, KEY_RIGHT,
	KEY_B, KEY_A,
]
## Seconds of idle before a partial sequence is thrown away.
const RESET_AFTER: float = 1.6
#endregion


#region State
var unlocked: bool = false
var noclip: bool = false
## Next index in SEQUENCE the player must hit.
var _index: int = 0
## Time since the last correct key.
var _idle: float = 0.0
var _hint: Label
#endregion


#region Lifecycle
func _ready() -> void:
	# Stay live if the tree is paused so the code still works from a pause screen.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if unlocked or _index == 0:
		return
	_idle += delta
	if _idle >= RESET_AFTER:
		_index = 0


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key := (event as InputEventKey).physical_keycode
	if unlocked:
		_cheat_key(key)
	else:
		_try_step(key)
#endregion


#region Konami
func _try_step(key: int) -> void:
	if _matches(key, SEQUENCE[_index]):
		_index += 1
		_idle = 0.0
		if _index >= SEQUENCE.size():
			_unlock()
		return
	# Wrong key: if it is the first step, start a new attempt, else reset hard.
	if _matches(key, SEQUENCE[0]):
		_index = 1
		_idle = 0.0
	else:
		_index = 0


## Directions accept arrows or WASD. B and A are letter keys only.
func _matches(key: int, expected: int) -> bool:
	match expected:
		KEY_UP:
			return key == KEY_UP or key == KEY_W
		KEY_DOWN:
			return key == KEY_DOWN or key == KEY_S
		KEY_LEFT:
			return key == KEY_LEFT or key == KEY_A
		KEY_RIGHT:
			return key == KEY_RIGHT or key == KEY_D
		_:
			return key == expected


func _unlock() -> void:
	_index = 0
	unlocked = true
	_build_hint()
	_refresh_hint()
	print("Dev cheats unlocked")
#endregion


#region Cheats
func _cheat_key(key: int) -> void:
	match key:
		KEY_N:
			noclip = not noclip
			_refresh_hint()
		KEY_K:
			Kinetum.kinetum = Kinetum.max_speed


func _build_hint() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 64
	add_child(layer)
	_hint = Label.new()
	_hint.position = Vector2(24, 24)
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.add_theme_color_override("font_color", Color(1.0, 0.312, 0.04, 0.9))
	layer.add_child(_hint)


func _refresh_hint() -> void:
	if _hint == null:
		return
	var noclip_state := "ON" if noclip else "off"
	_hint.text = "DEV\n[N] noclip %s\n[K] max kinetum" % noclip_state
#endregion
