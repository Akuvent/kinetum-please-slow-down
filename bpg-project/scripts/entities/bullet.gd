extends CharacterBody2D
## Homing bullet: outbound toward locked enemy, bounce on walls, return / parry / loose.
## One live instance at a time - spawned and owned by the player.

enum State { OUTBOUND, RETURN, AWAIT_PARRY, LOOSE }

#region Config
@export var parry_window_sec := 0.4
@export var turn_deg_per_sec := 720.0   # tune: lower = wider arcs
@export var path_arrive_radius := 50.0
@export var gradient: Gradient
#endregion


#region State
var state: State = State.OUTBOUND
## Copied from Kinetum each physics frame; player reads this while the shot is airborne.
var speed: float = Kinetum.kinetum
var player: Node2D  # set in setup()
## Locked enemy while outbound.
var seek_target: Node2D
## Live homing point (enemy or player), copied once per frame before steering.
var pathing_goal: Vector2
## Waypoints in global coords, pruned to direction changes. Repathed when LOS breaks or goal moves.
var path: PackedVector2Array
var path_index: int = 0
## Sampled once per frame so tracking() and the repath trigger agree on one value.
var has_los: bool = false
## Previous frame's has_los, kept for the "LOS just broke" repath edge trigger.
var had_los: bool = true
@onready var body_visual := $Polygon2D
#endregion


#region Lifecycle
func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING


func _physics_process(delta: float) -> void:
	Kinetum.set_outbound_active(state == State.OUTBOUND)
	speed = Kinetum.kinetum
	var ratio: float = (Kinetum.kinetum - 200.0) / (2000.0 - 200.0)
	ratio = clamp(ratio, 0.0, 1.0)
	if ratio:
		body_visual.color = gradient.sample(ratio)
	_refresh_pathing_goal()
	tracking(delta)
	queue_redraw()

func setup(p: Node2D) -> void:
	player = p
	find_target()
	# One-shot launch; OUTBOUND steering takes over after this.
	if is_instance_valid(seek_target):
		pathing_goal = seek_target.global_position
		_aim_at(pathing_goal)
#endregion


#region Movement
## Copy the live homing node into pathing_goal and refresh has_los for this frame.
func _refresh_pathing_goal() -> void:
	has_los = false
	match state:
		State.OUTBOUND:
			if is_instance_valid(seek_target):
				pathing_goal = seek_target.global_position
				has_los = _has_los_to(pathing_goal)
		State.RETURN:
			if is_instance_valid(player):
				pathing_goal = player.global_position
				has_los = _has_los_to(pathing_goal)


## Per-state steering, then the single move_and_collide for the frame.
func tracking(delta: float) -> void:
	match state:
		State.OUTBOUND:
			if is_instance_valid(seek_target):
				_track_toward_goal(delta)
		State.RETURN:
			if is_instance_valid(player):
				_track_toward_goal(delta)
		State.AWAIT_PARRY, State.LOOSE:
			# Fly-through or loose bounce, no homing / pathfollow.
			pass
		_:
			pass

	var collision := move_and_collide(velocity * delta)
	if collision:
		_resolve_collision(collision)

	check_parry_window()


func _track_toward_goal(delta: float) -> void:
	if has_los:
		_steer_toward(pathing_goal, delta)
	else:
		if had_los or _needs_repath():
			_get_path()
		if not _follow(delta):
			_steer_toward(pathing_goal, delta)
	had_los = has_los


## Instant set direction (spawn / return home / parry redirect).
func _aim_at(goal: Vector2) -> void:
	var dir := goal - global_position
	if dir.length() < 0.0001:
		return
	velocity = dir.normalized() * speed


## Soft aim_at: rotate toward the goal a little each frame (turn_deg_per_sec).
## Unlike _aim_at, this doesn't instantly overwrite velocity, so a wall bounce
## can actually move us before we curve back toward the target.
func _steer_toward(goal: Vector2, delta: float) -> void:
	var to_goal := goal - global_position
	if to_goal.length() < 0.0001 or velocity.length() < 0.0001:
		return
	var current := velocity.normalized()
	var desired := to_goal.normalized()
	var delta_angle := current.angle_to(desired)
	var max_turn := deg_to_rad(turn_deg_per_sec) * delta
	delta_angle = clampf(delta_angle, -max_turn, max_turn)
	velocity = current.rotated(delta_angle) * speed


## Steer at the current waypoint; advance path_index when close or passed.
func _follow(delta: float) -> bool:
	if path.is_empty() or path_index >= path.size():
		return false
	_steer_toward(path[path_index], delta)
	var waypoint := path[path_index]
	var passed := false
	if path_index > 0:
		var leg := path[path_index] - path[path_index - 1]
		passed = (global_position - waypoint).dot(leg) > 0.0
	if global_position.distance_to(waypoint) < path_arrive_radius or passed:
		path_index += 1
	return true


func _resolve_collision(collision: KinematicCollision2D) -> void:
	var collider := collision.get_collider()
	if collider == null:
		return

	if state == State.OUTBOUND and collider.has_method("hurt"):
		collider.hurt()
		play_vfx()
		state = State.RETURN
		path.clear()
		path_index = 0
		# Force a fresh return path; do not carry outbound LOS into the parry check this frame.
		had_los = false
		if is_instance_valid(player):
			pathing_goal = player.global_position
			if _has_los_to(pathing_goal):
				_aim_at(pathing_goal)
		return

	# Walls / geometry.
	velocity = velocity.bounce(collision.get_normal())
	if velocity.length() > 0.0001:
		velocity = velocity.normalized() * speed
#endregion


#region Targeting
## Nearest living enemy; group membership is the source of truth (hurt() frees them).
func find_target() -> void:
	var targets := get_tree().get_nodes_in_group("enemies")
	var best_distance: float = INF
	seek_target = null
	for enemy in targets:
		if not is_instance_valid(enemy):
			continue
		var dist_to_enemy: float = enemy.global_position.distance_to(global_position)
		if dist_to_enemy < best_distance:
			best_distance = dist_to_enemy
			seek_target = enemy


func check_parry_window() -> void:
	if not is_instance_valid(player):
		return
	var parry_radius := speed * parry_window_sec * 0.5
	# Wall-aware distance: straight line when clear, nav path length when blocked.
	var parry_dist := _parry_distance_to_player()
	if state == State.RETURN and parry_dist <= parry_radius:
		state = State.AWAIT_PARRY
	elif state == State.AWAIT_PARRY and parry_dist > parry_radius:
		state = State.LOOSE
		path.clear()
		Kinetum.set_loose(true)

	if Input.is_action_just_pressed("parry"):
		# Same wall-aware distance for clutch parries on a loose bullet.
		if state == State.AWAIT_PARRY or (state == State.LOOSE and parry_dist <= parry_radius):
			_do_parry()


func _do_parry() -> void:
	Kinetum.parried()
	find_target()
	if not is_instance_valid(seek_target):
		return
	path.clear()
	had_los = true
	state = State.OUTBOUND
	Kinetum.set_loose(false)
	pathing_goal = seek_target.global_position
	_aim_at(pathing_goal)
#endregion


#region Pathfinding
## How far the bullet is from the player for parry window enter / exit.
## Open air: straight-line pixels. Behind a wall: sum of A* segments (cannot clip through tiles).
func _parry_distance_to_player() -> float:
	if not is_instance_valid(player):
		return INF
	var goal := player.global_position
	# Ray is checked fresh here, not the cached has_los from the start of the frame.
	if _has_los_to(goal):
		return global_position.distance_to(goal)
	return _nav_path_length(global_position, goal)


## Total walkable distance between two world points on the shared level grid.
## Returns INF when no route exists (out of bounds or blocked).
func _nav_path_length(from: Vector2, to: Vector2) -> float:
	if Game.astar_grid == null:
		return INF
	var from_cell: Vector2i = Game.world_to_cell(from)
	var to_cell: Vector2i = Game.world_to_cell(to)
	if not Game.astar_grid.is_in_boundsv(from_cell) or not Game.astar_grid.is_in_boundsv(to_cell):
		return INF
	var astar_path: PackedVector2Array = Game.astar_grid.get_point_path(from_cell, to_cell)
	if astar_path.size() < 2:
		return INF
	var total: float = 0.0
	for i in range(1, astar_path.size()):
		total += astar_path[i - 1].distance_to(astar_path[i])
	return total


## Takes a Vector2 rather than a node so waypoints can be tested too.
func _has_los_to(target: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, target)
	query.collide_with_areas = false
	query.collision_mask = 1 # world
	query.exclude = [self]
	var hit := space.intersect_ray(query)
	return hit.is_empty()  # nothing between you and the target point


## True when the live goal has moved off the current path endpoint (e.g. player moved).
func _needs_repath() -> bool:
	if path.is_empty() or Game.astar_grid == null:
		return true
	return Game.world_to_cell(pathing_goal) != Game.world_to_cell(path[-1])


## Rebuild `path` from the shared grid, pruned to the points where it bends.
## Every early return leaves the previous path in place rather than clearing it.
func _get_path() -> void:
	if Game.astar_grid == null:
		return
	var bullet_cell: Vector2i = Game.world_to_cell(global_position)
	var target_cell: Vector2i = Game.world_to_cell(pathing_goal)
	# Out-of-bounds fails silently - the grid region only spans the painted tiles.
	if not Game.astar_grid.is_in_boundsv(bullet_cell) or not Game.astar_grid.is_in_boundsv(target_cell):
		return
	path = Game.astar_grid.get_point_path(bullet_cell, target_cell)
	if path.size() < 2:
		path.clear()
		return

	# path[0] is our own cell centre, which is behind us - start at path[1].
	var shortened_path: PackedVector2Array
	shortened_path.append(path[1])
	if path.size() >= 3:
		for i in range(2, path.size() - 1):
			var dir_in := (path[i] - path[i - 1]).normalized()
			var dir_out := (path[i + 1] - path[i]).normalized()
			if not dir_in.is_equal_approx(dir_out):
				shortened_path.append(path[i])
	shortened_path.append(path[-1])
	path = shortened_path
	path_index = 0
#endregion


#region FX
func play_vfx() -> void:
	pass # To be used later
#endregion


#region Debug
func _draw() -> void:
	var local_path: PackedVector2Array
	for point in path:
		local_path.append(to_local(point))
	if path.size() >= 2:
		draw_polyline(local_path, Color(0.0, 0.0, 1.0, 1.0))
	if path.is_empty():
		return
	if path_index >= 0 and path_index < path.size():
		draw_circle(to_local(path[path_index]), 10.0, Color(0.0, 1.0, 0.376, 1.0))
#endregion
