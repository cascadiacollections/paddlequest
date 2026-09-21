extends AnimatableBody3D

## The paddle is kinematic and driven from the controller here in
## _physics_process rather than being parented to it: AnimatableBody3D only
## pushes its transform to the physics server when the transform is written on
## the body itself, so parenting would leave us with a collider that renders in
## the right place but never actually moves.

@export var controller_path: NodePath
## Offset from the controller to the blade centre, in controller-local
## space. The handle joins the blade at its rim and rakes back, so the blade
## sits above and ahead of the hand rather than straight out in front of it.
##
## This is the fallback, measured against Touch controllers. Devices whose grip
## pose sits somewhere else get an entry in PROFILE_GRIPS below.
@export var grip_offset := Vector3(0.0, 0.228, -0.133)
## Tilt of the paddle face about the grip axis, in degrees.
@export var grip_tilt_degrees := 0.0
@export var haptic_strength := 0.6
@export var haptic_duration := 0.08

## Per-interaction-profile grip overrides, as {offset, tilt}. OpenXR's grip
## pose is defined relative to the physical controller, so a device with a
## different shape puts the hand somewhere else relative to the blade. Getting
## this wrong does not look broken - the paddle just sits slightly wrong in the
## hand, which is exactly the kind of thing you only notice wearing it.
##
## Steam Frame is NOT yet measured on hardware: it currently inherits the Touch
## numbers so the paddle is in roughly the right place, and wants a pass with
## the headset on. See README "Per-device grip offsets".
const PROFILE_GRIPS := {
	"/interaction_profiles/valve/frame_controller_valve": {
		"offset": Vector3(0.0, 0.228, -0.133),
		"tilt": 0.0,
	},
}

## World-space velocity of the paddle, sampled across physics frames. A
## kinematic body always reports zero linear velocity, so without this the ball
## would take no energy from a swing.
var swing_velocity := Vector3.ZERO

var _controller: XRController3D
var _last_origin := Vector3.ZERO
var _sampled := false

## Resolved from the active interaction profile; falls back to the exports.
var _grip_offset := grip_offset
var _grip_tilt := grip_tilt_degrees

# Desktop-only fallback so the demo is playable without a headset.
var _flat_mode := false
var _flat_aim := Vector2(0.0, 0.0)


func _ready() -> void:
	sync_to_physics = true
	_controller = get_node_or_null(controller_path) as XRController3D
	_apply_profile("")
	if _controller != null:
		# Emitted once the runtime binds a profile to this controller, which
		# happens after _ready and can happen again if the player swaps
		# controllers mid-session.
		_controller.profile_changed.connect(_apply_profile)


## Pick the grip geometry for whichever controller the runtime bound. An
## unknown or absent profile keeps the exported fallback.
func _apply_profile(profile: String) -> void:
	var grip: Dictionary = PROFILE_GRIPS.get(profile, {})
	_grip_offset = grip.get("offset", grip_offset)
	_grip_tilt = grip.get("tilt", grip_tilt_degrees)


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

	var target := _controller.global_transform.translated_local(_grip_offset)
	if not is_zero_approx(_grip_tilt):
		target.basis = target.basis * Basis(Vector3.RIGHT, deg_to_rad(_grip_tilt))
	return target


func pulse() -> void:
	if _controller != null:
		_controller.trigger_haptic_pulse(
			"haptic", 0.0, haptic_strength, haptic_duration, 0.0
		)
