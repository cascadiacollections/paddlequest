extends AnimatableBody3D

## The paddle is kinematic and driven from the controller here in
## _physics_process rather than being parented to it: AnimatableBody3D only
## pushes its transform to the physics server when the transform is written on
## the body itself, so parenting would leave us with a collider that renders in
## the right place but never actually moves.

@export var controller_path: NodePath
## Offset from the controller origin, in controller-local space.
@export var grip_offset := Vector3(0.0, 0.0, -0.18)
## Tilt of the paddle face about the grip axis, in degrees.
@export var grip_tilt_degrees := 0.0
@export var haptic_strength := 0.6
@export var haptic_duration := 0.08

## World-space velocity of the paddle, sampled across physics frames. A
## kinematic body always reports zero linear velocity, so without this the ball
## would take no energy from a swing.
var swing_velocity := Vector3.ZERO

var _controller: XRController3D
var _last_origin := Vector3.ZERO
var _sampled := false

# Desktop-only fallback so the demo is playable without a headset.
var _flat_mode := false
var _flat_aim := Vector2(0.0, 0.0)


func _ready() -> void:
	sync_to_physics = true
	_controller = get_node_or_null(controller_path) as XRController3D


func set_flat_mode(enabled: bool) -> void:
	_flat_mode = enabled
	if enabled:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if _flat_mode and event is InputEventMouseMotion:
		_flat_aim += event.relative * 0.004
		_flat_aim.x = clampf(_flat_aim.x, -1.2, 1.2)
		_flat_aim.y = clampf(_flat_aim.y, -0.8, 0.8)


func _physics_process(delta: float) -> void:
	if delta <= 0.0:
		return

	var target := _target_transform()
	if _sampled:
		swing_velocity = (target.origin - _last_origin) / delta
	else:
		_sampled = true
	_last_origin = target.origin
	global_transform = target


func _target_transform() -> Transform3D:
	if _flat_mode or _controller == null:
		# Slide the paddle around a plane in front of the player with the mouse.
		var origin := Vector3(_flat_aim.x, 1.3 - _flat_aim.y, -0.45)
		return Transform3D(Basis.IDENTITY, origin)

	var target := _controller.global_transform.translated_local(grip_offset)
	if not is_zero_approx(grip_tilt_degrees):
		target.basis = target.basis * Basis(Vector3.RIGHT, deg_to_rad(grip_tilt_degrees))
	return target


func pulse() -> void:
	if _controller != null:
		_controller.trigger_haptic_pulse(
			"haptic", 0.0, haptic_strength, haptic_duration, 0.0
		)
