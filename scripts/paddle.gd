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

## Weight given to the newest frame when smoothing the swing sample. 1.0 is
## no smoothing at all. At 90Hz there is very little room here: smooth too
## hard and a gentle tap converges with a hard swing, which is the one
## distinction this whole derivation exists to preserve.
@export_range(0.1, 1.0, 0.05) var swing_smoothing := 0.6
## Ceiling on the sampled swing speed, m/s. A human arm does not swing a
## paddle at 30 m/s; anything claiming to is tracking noise, and ball.gd
## multiplies it straight into an impulse with no clamp of its own.
@export var max_swing_speed := 12.0

const FRAME_CONTROLLER := "/interaction_profiles/valve/frame_controller_valve"

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
	FRAME_CONTROLLER: {"offset": Vector3(0.0, 0.228, -0.133), "tilt": 0.0},
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
		# A controller that drops out and comes back reappears somewhere else.
		_controller.tracking_changed.connect(_on_tracking_changed)


func _on_tracking_changed(_tracking: bool) -> void:
	reset_swing()


## Pick the grip geometry for whichever controller the runtime bound. An
## unknown or absent profile keeps the exported fallback.
func _apply_profile(profile: String) -> void:
	var grip: Dictionary = PROFILE_GRIPS.get(profile, {})
	var offset: Vector3 = grip.get("offset", grip_offset)
	var tilt: float = grip.get("tilt", grip_tilt_degrees)
	if offset == _grip_offset and is_equal_approx(tilt, _grip_tilt):
		return
	_grip_offset = offset
	_grip_tilt = tilt
	# The blade centre just moved relative to the hand. That displacement is
	# not a swing, so do not let the next frame read it as one.
	reset_swing()


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
		var raw := (target.origin - _last_origin) / delta
		# One frame of tracking jitter used to become one launched ball: this
		# feeds ball.gd's impulse directly. Smooth it, then clamp what is left.
		swing_velocity = swing_velocity.lerp(raw, swing_smoothing)
		if swing_velocity.length() > max_swing_speed:
			swing_velocity = swing_velocity.normalized() * max_swing_speed
	else:
		_sampled = true
	_last_origin = target.origin
	global_transform = target


## Drop the sampled swing and start again from the next frame. Used whenever
## the paddle's position jumps for a reason that is not the player swinging
## it - tracking lost and regained, or the grip offset changing under us -
## since the difference across that jump is not a swing and would read as an
## enormous one.
func reset_swing() -> void:
	_sampled = false
	swing_velocity = Vector3.ZERO


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
		_controller.trigger_haptic_pulse("haptic", 0.0, haptic_strength, haptic_duration, 0.0)
