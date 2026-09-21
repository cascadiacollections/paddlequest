extends XROrigin3D

## Left thumbstick: X strafes, pushing down crouches, pushing up stands back up.
## Right thumbstick Y moves forward and back, since the left stick's Y axis is
## spent on crouching.
##
## Movement is relative to where the player is looking rather than where the
## origin happens to face, which is what people expect once they have turned
## their head away from the front wall.

## Emitted while the player is being moved or turned artificially, so the
## vignette knows to close in. True on the frame motion starts, false on the
## frame it stops.
signal motion_changed(moving: bool)

@export var controller_path: NodePath
@export var forward_controller_path: NodePath
@export var speed := 2.2
@export var deadzone := 0.2
@export var crouch_depth := 0.75
@export var crouch_speed := 1.8
## The court is built from colliders but the XR origin is not a physics body,
## so without this the player walks straight through a wall.
@export var bounds_min := Vector2(-2.6, -5.5)
@export var bounds_max := Vector2(2.6, 2.1)

## Snap turn, on the right thumbstick's X axis. Snapping rather than sweeping
## is the single biggest comfort lever in artificial locomotion: a smooth
## yaw is what makes people ill, and a discrete jump gives the inner ear
## nothing to disagree with.
@export var snap_turn_degrees := 30.0
## Smooth turn rate, used only when snap turn is switched off.
@export var smooth_turn_speed := 90.0
## How far the origin drops in seated mode, so a seated player's head still
## arrives at rally height.
@export var seated_drop := 0.45

@onready var _camera: XRCamera3D = $XRCamera3D

var _controller: XRController3D
var _forward_controller: XRController3D
var _crouch := 0.0
var _base_y := 0.0
var _turn_armed := true
var _moving := false
var _snap_turn := true
var _seated := false


func _ready() -> void:
	_controller = get_node_or_null(controller_path) as XRController3D
	_forward_controller = get_node_or_null(forward_controller_path) as XRController3D
	_base_y = position.y
	apply_comfort_settings()


## Re-read the comfort settings. Called at startup and whenever the pause
## menu changes one, so a toggle takes effect without a restart.
func apply_comfort_settings() -> void:
	_snap_turn = SaveGame.load_setting("snap_turn")
	set_seated(SaveGame.load_setting("seated"))


func set_seated(seated: bool) -> void:
	_seated = seated


func _process(delta: float) -> void:
	var stick := _read_stick()
	var moved := _move(stick.x, _read_forward(), delta)
	var turned := _turn(_read_turn(), delta)
	_crouch_toward(stick.y, delta)

	var moving := moved or turned
	if moving != _moving:
		_moving = moving
		motion_changed.emit(moving)


## Right thumbstick X. The left stick's X strafes and its Y crouches, and the
## right stick's Y moves forward, so this is the one axis left.
func _read_turn() -> float:
	if _forward_controller != null:
		var stick := _forward_controller.get_vector2("primary")
		if absf(stick.x) > deadzone:
			return stick.x
	return Input.get_axis("ui_focus_prev", "ui_focus_next")


## Yaw the origin about the player's head rather than its own origin: in
## roomscale the two can be a metre apart, and turning about the origin
## swings the player through an arc instead of rotating them in place.
func _turn(amount: float, delta: float) -> bool:
	if absf(amount) < deadzone:
		_turn_armed = true
		return false

	var degrees := 0.0
	if _snap_turn:
		if not _turn_armed:
			return false
		_turn_armed = false
		degrees = snap_turn_degrees * signf(amount)
	else:
		degrees = smooth_turn_speed * amount * delta

	var pivot := _camera.global_position
	var offset := global_position - pivot
	var rotated := offset.rotated(Vector3.UP, deg_to_rad(-degrees))
	global_position = pivot + rotated
	rotate_y(deg_to_rad(-degrees))
	return true


func _read_stick() -> Vector2:
	if _controller != null:
		var stick := _controller.get_vector2("primary")
		if stick.length() > deadzone:
			return stick
	# Arrow keys stand in for the thumbstick so locomotion is testable flat.
	return Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_down", "ui_up"))


func _read_forward() -> float:
	if _forward_controller != null:
		var stick := _forward_controller.get_vector2("primary")
		if stick.length() > deadzone:
			return stick.y
	return Input.get_axis("ui_page_down", "ui_page_up")


func _move(strafe: float, forward: float, delta: float) -> bool:
	if absf(strafe) < 0.001 and absf(forward) < 0.001:
		return false

	var basis := _camera.global_transform.basis
	var right := basis.x
	var ahead := -basis.z
	right.y = 0.0
	ahead.y = 0.0
	if right.length_squared() < 0.0001 or ahead.length_squared() < 0.0001:
		return false

	var motion := (right.normalized() * strafe + ahead.normalized() * forward) * speed * delta
	# Clamp where the head ends up rather than the origin: in roomscale the two
	# can be a metre apart, and clamping the origin still lets the head clip a
	# wall.
	var head := _camera.global_position + motion
	head.x = clampf(head.x, bounds_min.x, bounds_max.x)
	head.z = clampf(head.z, bounds_min.y, bounds_max.y)

	var applied := head - _camera.global_position
	applied.y = 0.0
	global_position += applied
	return applied.length_squared() > 0.0


func _crouch_toward(amount: float, delta: float) -> void:
	var target := _crouch
	if amount < -deadzone:
		target = crouch_depth
	elif amount > deadzone:
		target = 0.0

	_crouch = move_toward(_crouch, target, crouch_speed * delta)
	position.y = _base_y - _crouch - (seated_drop if _seated else 0.0)
