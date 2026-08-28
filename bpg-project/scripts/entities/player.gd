extends CharacterBody2D
## Player: move (speed tied to kinetum) + parry on bullet return.
## One live bullet: the instance is created with the player and added to the scene on fire.

#region Config
var bullet_scene: PackedScene = preload("res://scenes/entities/bullet.tscn")
const JUMP_VELOCITY: float = -600.0
## How long to hold the land pose (seconds). Bump if it still feels snappy.
const LAND_HOLD: float = 0.2
## Grace period after leaving a platform where jump still works.
const COYOTE_TIME: float = 0.10
## How long a jump press is remembered before landing.
const JUMP_BUFFER_TIME: float = 0.10
@export var facing_right: bool = true
#endregion


#region Node refs
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var muzzle: Marker2D = $Muzzle
#endregion


#region State
## The one bullet; lives on the player until fired, then stays in the world.
var bullet = bullet_scene.instantiate()
## Matches bullet speed while the shot is airborne; floor of 50.
var speed: float = 100
var base_speed: float = 100 # for jump mult
var max_kinetum_jump_mult: float = 1.5
## Editor position is for facing right; X is mirrored when facing left.
var _muzzle_offset: Vector2 = Vector2.ZERO
## False during the land pose so fire doesn't interrupt it.
var can_shoot: bool = true
## True until the one bullet is fired (this slice never re-holsters).
var bullet_left: bool = true
## Floor state sampled at the start of the physics frame (before move_and_slide).
var was_on_floor: bool = true
var _landing: bool = false
var _land_timer: float = 0.0
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var kinetum_jump_mult: float = 1.0
#endregion


#region Lifecycle
func _ready() -> void:
	_muzzle_offset = muzzle.position
	_apply_facing()


func _physics_process(delta: float) -> void:
	was_on_floor = is_on_floor()
	if not bullet_left:
		speed = maxf(bullet.speed, 50)

	_update_jump_timers(delta)
	_apply_gravity_and_jump(delta)
	_apply_horizontal_move()
	_try_fire()

	move_and_slide()
	_update_anims(delta)
#endregion


#region Movement
func _update_jump_timers(delta: float) -> void:
	if is_on_floor():
		_coyote_timer = COYOTE_TIME
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)

	_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)
	if Input.is_action_just_pressed("move_up"):
		_jump_buffer_timer = JUMP_BUFFER_TIME


func _apply_gravity_and_jump(delta: float) -> void:
	if not was_on_floor:
		velocity += get_gravity() * delta

	var can_jump := is_on_floor() or _coyote_timer > 0.0
	var wants_jump := _jump_buffer_timer > 0.0
	if can_jump and wants_jump:
		_perform_jump()


func _perform_jump() -> void:
	var kinetum_t := clampf(inverse_lerp(base_speed, Kinetum.max_speed, speed), 0.0, 1.0)
	kinetum_jump_mult = lerpf(1.0, max_kinetum_jump_mult, sqrt(kinetum_t))
	velocity.y = JUMP_VELOCITY * kinetum_jump_mult
	_landing = false
	_coyote_timer = 0.0
	_jump_buffer_timer = 0.0


func _apply_horizontal_move() -> void:
	var direction := Input.get_axis("move_left", "move_right")
	if direction:
		var move_speed := speed * 1.5 if Input.is_action_pressed("run") else speed
		velocity.x = direction * move_speed
		facing_right = direction > 0
		_apply_facing()
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
#endregion


#region Combat
func _try_fire() -> void:
	if Input.is_action_just_pressed("fire") and bullet_left and can_shoot:
		bullet.global_position = muzzle.global_position
		get_tree().current_scene.add_child(bullet)
		bullet.setup(self)
		bullet_left = false
#endregion


#region Facing
func _apply_facing() -> void:
	# Art faces right by default; flip when looking left.
	sprite.flip_h = not facing_right
	muzzle.position = Vector2(
		_muzzle_offset.x if facing_right else -_muzzle_offset.x,
		_muzzle_offset.y
	)
#endregion


#region Animation
func _update_anims(delta: float) -> void:
	# Just landed this frame.
	if is_on_floor() and not was_on_floor:
		_landing = true
		can_shoot = false
		_land_timer = LAND_HOLD
		_set_anim(&"land_anim")

	if _landing:
		# Cancel land early: left the floor, or started walking.
		if not is_on_floor() or absf(velocity.x) > 0.1:
			_landing = false
			can_shoot = true
		else:
			_land_timer -= delta
			if _land_timer <= 0.0:
				_landing = false
				can_shoot = true
			else:
				return

	if not is_on_floor():
		if velocity.y >= 0:
			_set_anim(&"fall_anim")
		else:
			_set_anim(&"jump_anim")
	elif absf(velocity.x) > 0.1:
		if Input.is_action_pressed("run"):
			_set_anim(&"run_anim")
		else:
			_set_anim(&"walk_anim")
	else:
		_set_anim(&"idle_anim")


func _set_anim(anim_name: StringName) -> void:
	if sprite.animation != anim_name:
		sprite.play(anim_name)
#endregion
