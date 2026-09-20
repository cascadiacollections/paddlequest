extends XROrigin3D

## Left thumbstick: X strafes, pushing down crouches, pushing up stands back up.
## Right thumbstick Y moves forward and back, since the left stick's Y axis is
## spent on crouching.
##
## Movement is relative to where the player is looking rather than where the
## origin happens to face, which is what people expect once they have turned
## their head away from the front wall.

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

@onready var _camera: XRCamera3D = $XRCamera3D

var _controller: XRController3D
var _forward_controller: XRController3D
var _crouch := 0.0
var _base_y := 0.0


func _ready() -> void:
	_controller = get_node_or_null(controller_path) as XRController3D
	_forward_controller = get_node_or_null(forward_controller_path) as XRController3D
	_base_y = position.y


func _process(delta: float) -> void:
	var stick := _read_stick()
	_move(stick.x, _read_forward(), delta)
	_crouch_toward(stick.y, delta)


func _read_stick() -> Vector2:
	if _controller != null:
		var stick := _controller.get_vector2("primary")
		if stick.length() > deadzone:
			return stick
	# Arrow keys stand in for the thumbstick so locomotion is testable flat.
	return Vector2(
		Input.get_axis("ui_left", "ui_right"),
		Input.get_axis("ui_down", "ui_up")
	)


func _read_forward() -> float:
	if _forward_controller != null:
		var stick := _forward_controller.get_vector2("primary")
		if stick.length() > deadzone:
			return stick.y
	return Input.get_axis("ui_page_down", "ui_page_up")


func _move(strafe: float, forward: float, delta: float) -> void:
	if absf(strafe) < 0.001 and absf(forward) < 0.001:
		return

	var basis := _camera.global_transform.basis
	var right := basis.x
	var ahead := -basis.z
	right.y = 0.0
	ahead.y = 0.0
	if right.length_squared() < 0.0001 or ahead.length_squared() < 0.0001:
		return

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


func _crouch_toward(amount: float, delta: float) -> void:
	var target := _crouch
	if amount < -deadzone:
		target = crouch_depth
	elif amount > deadzone:
		target = 0.0

	_crouch = move_toward(_crouch, target, crouch_speed * delta)
	position.y = _base_y - _crouch
