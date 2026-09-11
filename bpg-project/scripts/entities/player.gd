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
## Fall speed below this skips land dust entirely.
const LAND_DUST_MIN_FALL: float = 180.0
## Fall speed at which land dust reaches full strength.
const LAND_DUST_MAX_FALL: float = 850.0
@export var facing_right: bool = true
#endregion


#region Node refs
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var muzzle: Marker2D = $Muzzle
@onready var land_dust_spawn: Marker2D = $ParticlePos
@onready var land_dust_particles: GPUParticles2D = $LandGPUParticles2D
@onready var camera: Camera2D = $Camera2D
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
const JUMP_CUT_MULT: float = 0.5
var _fastest_fall_speed_while_airborne: float = 0.0
var _land_dust_material: ParticleProcessMaterial
var _remaining_camera_shake: float = 0.0
## World mask to restore when noclip turns off.
var _world_collision_mask: int = 1
## Local copy of DevCheats.noclip so we only retune collision on change.
var _noclip_on: bool = false
#endregion


#region Lifecycle
func _ready() -> void:
	_muzzle_offset = muzzle.position
	_world_collision_mask = collision_mask
	_land_dust_material = land_dust_particles.process_material.duplicate() as ParticleProcessMaterial
	land_dust_particles.process_material = _land_dust_material
	_apply_facing()
	_sync_noclip()


func _physics_process(delta: float) -> void:
	_sync_noclip()
	was_on_floor = is_on_floor()
	if not bullet_left:
		speed = maxf(bullet.speed, 50)

	if _noclip_on:
		# Skip gravity and jump. Fly in all four directions instead.
		_apply_noclip_move()
		_try_fire()
		move_and_slide()
		_update_camera_shake(delta)
		_update_anims(delta)
		return

	_update_jump_timers(delta)
	_apply_gravity_and_jump(delta)
	_apply_horizontal_move()
	_try_fire()

	if not was_on_floor:
		_fastest_fall_speed_while_airborne = maxf(_fastest_fall_speed_while_airborne, velocity.y)

	move_and_slide()
	_update_camera_shake(delta)
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
	if Input.is_action_just_released("move_up") and velocity.y < 0:
		velocity.y *= JUMP_CUT_MULT
	var can_jump := is_on_floor() or _coyote_timer > 0.0
	var wants_jump := _jump_buffer_timer > 0.0
	if can_jump and wants_jump:
		_perform_jump()


func _perform_jump() -> void:
	var speed_ratio_of_max_kinetum := clampf(inverse_lerp(base_speed, Kinetum.max_speed, speed), 0.0, 1.0)
	kinetum_jump_mult = lerpf(1.0, max_kinetum_jump_mult, sqrt(speed_ratio_of_max_kinetum))
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


func _sync_noclip() -> void:
	if DevCheats.noclip == _noclip_on:
		return
	_noclip_on = DevCheats.noclip
	# Mask 0 = ignore world tiles. Shape stays on so we can restore cleanly.
	collision_mask = 0 if _noclip_on else _world_collision_mask
	if _noclip_on:
		velocity = Vector2.ZERO


func _apply_noclip_move() -> void:
	var move := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	if move.length_squared() > 1.0:
		move = move.normalized()
	var fly := speed * 1.5 if Input.is_action_pressed("run") else speed
	# 1.5x on top of run so flying a level is faster than walking it.
	velocity = move * fly * 1.5
	if move.x != 0.0:
		facing_right = move.x > 0.0
		_apply_facing()
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


#region VFX
func _play_land_dust(fastest_fall_speed: float) -> void:
	if fastest_fall_speed < LAND_DUST_MIN_FALL:
		return

	var landing_hardness_ratio := clampf(
		inverse_lerp(LAND_DUST_MIN_FALL, LAND_DUST_MAX_FALL, fastest_fall_speed), 0.0, 1.0
	)
	var speed_ratio_of_max_kinetum := clampf(inverse_lerp(base_speed, Kinetum.max_speed, speed), 0.0, 1.0)
	var land_dust_strength := clampf(
		landing_hardness_ratio * lerpf(0.75, 1.0, speed_ratio_of_max_kinetum), 0.0, 1.0
	)

	land_dust_particles.position = land_dust_spawn.position
	land_dust_particles.amount = int(lerpf(6.0, 22.0, land_dust_strength))
	_land_dust_material.spread = lerpf(55.0, 95.0, land_dust_strength)
	_land_dust_material.initial_velocity_min = lerpf(22.0, 45.0, land_dust_strength)
	_land_dust_material.initial_velocity_max = lerpf(65.0, 150.0, land_dust_strength)
	_land_dust_material.scale_max = lerpf(0.9, 1.8, land_dust_strength)

	var horizontal_movement_ratio := clampf(absf(velocity.x) / maxf(speed, 1.0), 0.0, 1.0)
	_land_dust_material.emission_shape_scale.x = lerpf(16.0, 34.0, horizontal_movement_ratio)

	var dust_horizontal_drift := 0.0
	if absf(velocity.x) > 10.0:
		dust_horizontal_drift = signf(velocity.x) * lerpf(0.15, 0.45, horizontal_movement_ratio)
	_land_dust_material.direction = Vector3(dust_horizontal_drift, -1.0, 0.0).normalized()

	land_dust_particles.restart()

	if land_dust_strength > 0.65:
		_remaining_camera_shake = lerpf(1.5, 4.5, land_dust_strength)


func _update_camera_shake(delta: float) -> void:
	if _remaining_camera_shake <= 0.0:
		camera.offset = Vector2.ZERO
		return

	_remaining_camera_shake = maxf(_remaining_camera_shake - delta * 18.0, 0.0)
	var camera_shake_offset := _remaining_camera_shake * 0.35
	camera.offset = Vector2(
		randf_range(-camera_shake_offset, camera_shake_offset),
		randf_range(-camera_shake_offset, camera_shake_offset)
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
		_play_land_dust(_fastest_fall_speed_while_airborne)
		_fastest_fall_speed_while_airborne = 0.0
		

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
