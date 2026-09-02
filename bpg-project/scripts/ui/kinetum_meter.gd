extends Node2D
## Readable expression of shared bullet/player speed (kinetum).
## Bind to Kinetum; do not keep a parallel value here.
@onready var fill := $KinetumBarFill
@onready var panel := $PanelContainer
@export var gradient: Gradient
@export var min_scroll_speed: float = 0.05
@export var max_scroll_speed: float = 2.0
var lerp_speed: float = 8.0
var displayed_kinetum : float = 0.0
var default_pos: Vector2
var dash_material: ShaderMaterial
var fill_material: ShaderMaterial


func _ready() -> void:
	displayed_kinetum = Kinetum.kinetum
	default_pos = self.position
	dash_material = panel.material as ShaderMaterial
	fill_material = fill.material as ShaderMaterial


func _process(delta: float) -> void:
	displayed_kinetum = lerp(displayed_kinetum, Kinetum.kinetum, lerp_speed * delta)

	var ratio: float = (displayed_kinetum - 200.0) / (2000.0 - 200.0)
	ratio = clamp(ratio, 0.0, 1.0)
	var scroll_speed := lerpf(min_scroll_speed, max_scroll_speed, ratio)
	if fill_material:
		fill_material.set_shader_parameter("progress", ratio)
		fill_material.set_shader_parameter("tint", gradient.sample(ratio))
		fill_material.set_shader_parameter("scroll_speed", scroll_speed)
	if dash_material:
		dash_material.set_shader_parameter("scroll_speed", scroll_speed)
	var intensity : float = pow(ratio, 4.0) * 4
	shake(intensity, delta)


func shake(intensity: float, delta: float) -> void:
	if intensity <= 0.0:
		self.position = default_pos
		return
	var offset := Vector2(
		sin(Time.get_ticks_msec() * 0.04) * intensity,
		sin(Time.get_ticks_msec() * 0.053) * intensity
	)
	self.position = default_pos + offset
