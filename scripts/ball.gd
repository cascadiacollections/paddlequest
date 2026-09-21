extends RigidBody3D

signal wall_hit(rally: int)
signal paddle_hit(impact: float)

## Speed floor. Without it the ball bleeds energy into the floor and the rally
## dies of its own accord instead of because you missed.
@export var serve_speed := 7.0
@export var min_speed := 5.0
## Floor on horizontal speed, to stop the ball settling into a vertical loop.
@export var min_horizontal := 1.5
## Speed ceiling a rally starts at. Authored value: never written at runtime.
## The live ceiling is _max_speed, which climbs by rally_gain off the front
## wall and resets here on every serve.
@export var base_max_speed := 16.0
## Hard ceiling the rally gain can never push past, however long the rally.
@export var absolute_max_speed := 22.0
## How much of a swing carries into the ball, on top of the elastic bounce.
@export var swing_transfer := 0.8
## Ball speeds up every time it comes off the front wall.
@export var rally_gain := 1.03

## Curves the returning ball towards the paddle so it stays reachable.
## 0 is off (honest physics), 1 homes hard. Defaulted on for local dev; drop it
## towards 0 as the demo gets easier to play.
@export_range(0.0, 1.0, 0.05) var assist := 0.5
## Peak steering rate in radians-ish per second at assist = 1.
@export var assist_rate := 6.0

## Set by game.gd - what the assist steers towards.
var assist_target: Node3D

@onready var _bonk: AudioStreamPlayer3D = $Bonk

var _pending_impulse := Vector3.ZERO
var _rally := 0
var _serving := true
## Live speed ceiling for the rally in progress. Reset by serve().
var _max_speed := base_max_speed


func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	# A 16 m/s ball crosses a 2.5 cm paddle in well under one physics tick.
	continuous_cd = true
	body_entered.connect(_on_body_entered)


func serve(from: Vector3, toward: Vector3) -> void:
	_rally = 0
	_serving = true
	_max_speed = base_max_speed
	_pending_impulse = Vector3.ZERO
	freeze = true
	global_position = from
	freeze = false
	# Aim ballistically rather than straight down the line at the target. At
	# this gravity the ball drops the better part of a metre crossing the
	# court, which had the rally arriving around knee height.
	var delta := toward - from
	var flat := Vector3(delta.x, 0.0, delta.z)
	var flight := flat.length() / serve_speed
	var drop := 0.5 * _gravity_accel() * flight * flight
	linear_velocity = (
		flat.normalized() * serve_speed + Vector3.UP * ((delta.y + drop) / maxf(flight, 0.001))
	)
	angular_velocity = Vector3.ZERO


func _gravity_accel() -> float:
	return float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * gravity_scale


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# Velocity changes are applied here rather than inside the contact signal,
	# where writing to linear_velocity mid-solve gets partially overwritten.
	if _pending_impulse != Vector3.ZERO:
		state.linear_velocity += _pending_impulse
		_pending_impulse = Vector3.ZERO

	# A ball trapped bouncing floor-to-ceiling never reaches the front wall or
	# the miss zone, so the rally can neither score nor end. Bias it back
	# towards the wall whenever it goes near-vertical, preserving its speed.
	var horizontal := Vector2(state.linear_velocity.x, state.linear_velocity.z)
	if horizontal.length() < min_horizontal:
		var speed_before := state.linear_velocity.length()
		state.linear_velocity.z -= min_horizontal
		if speed_before > 0.01:
			state.linear_velocity = state.linear_velocity.normalized() * speed_before

	_apply_assist(state)

	var speed := state.linear_velocity.length()
	if speed > _max_speed:
		state.linear_velocity = state.linear_velocity.normalized() * _max_speed
	elif speed < min_speed and not _serving:
		state.linear_velocity = state.linear_velocity.normalized() * min_speed


func _apply_assist(state: PhysicsDirectBodyState3D) -> void:
	if assist <= 0.0 or assist_target == null or _serving:
		return
	# Only help on the return leg. Steering the outgoing shot would feel like
	# the ball ignoring where you aimed it.
	if state.linear_velocity.z <= 0.0:
		return

	var speed := state.linear_velocity.length()
	var to_target := assist_target.global_position - global_position
	if speed < 0.01 or to_target.length_squared() < 0.0001:
		return

	# Rotate the velocity towards the paddle instead of adding force to it:
	# adding force would also add energy, and the rally would accelerate on its
	# own regardless of how you hit the ball.
	var weight := clampf(assist * assist_rate * state.step, 0.0, 1.0)
	var steered := state.linear_velocity.normalized().lerp(to_target.normalized(), weight)
	if steered.length_squared() > 0.0001:
		state.linear_velocity = steered.normalized() * speed


func _on_body_entered(body: Node) -> void:
	var impact := linear_velocity.length()
	# The speed floor stays off until the ball is genuinely in play, so the
	# serve can start gently without being yanked up to rally pace.
	_serving = false

	if body.is_in_group("paddle"):
		_apply_swing(body)
		paddle_hit.emit(impact)
	elif body.is_in_group("front_wall"):
		_rally += 1
		_max_speed = minf(_max_speed * rally_gain, absolute_max_speed)
		wall_hit.emit(_rally)

	_play_bonk(impact)


func _apply_swing(paddle: Node3D) -> void:
	# Only the part of the swing driving the ball off the paddle face counts;
	# sliding the paddle sideways should not launch the ball.
	var face := -paddle.global_transform.basis.z
	var push: float = maxf(paddle.swing_velocity.dot(face), 0.0)
	_pending_impulse = face * push * swing_transfer


func _play_bonk(impact: float) -> void:
	if _bonk == null:
		return
	_bonk.pitch_scale = clampf(0.75 + impact * 0.05, 0.75, 1.8)
	_bonk.volume_db = _impact_volume_db(impact)
	_bonk.play()


func _impact_volume_db(impact: float) -> float:
	return clampf(-18.0 + impact * 1.5, -18.0, -2.0)
