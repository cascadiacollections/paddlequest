extends PaddleTest

## swing_velocity is the most physics-critical derivation in the project and
## had no coverage at all. A kinematic body reports zero velocity, so the
## paddle samples its own position across physics frames - which means one
## frame of tracking jitter used to become one launched ball, since ball.gd
## multiplies the result straight into an impulse.
##
## Headless there is no controller, so the paddle takes its flat-mode path and
## follows _flat_aim. That makes the sample deterministic: moving _flat_aim by
## d in one physics frame is a raw velocity of d * PHYSICS_HZ.

var paddle: AnimatableBody3D


func before_each() -> void:
	await build_scene()
	paddle = main.get_node("Paddle")
	paddle.set("_flat_aim", Vector2.ZERO)
	await step(4)


## Move the paddle by `delta_x` over a single physics frame and report the
## swing speed that came out of it.
func _nudge(delta_x: float) -> float:
	var aim: Vector2 = paddle.get("_flat_aim")
	paddle.set("_flat_aim", aim + Vector2(delta_x, 0.0))
	await step(1)
	return paddle.swing_velocity.length()


func test_a_stationary_paddle_reports_no_swing() -> void:
	await step(10)
	assert_almost_eq(paddle.swing_velocity.length(), 0.0, 0.01, "a paddle at rest is not swinging")


func test_moving_the_paddle_registers_a_swing() -> void:
	var speed := await _nudge(0.1)
	assert_gt(speed, 0.5, "moving the paddle should register as a swing")


func test_a_hard_swing_still_outpaces_a_gentle_tap() -> void:
	# The whole reason this derivation exists. Smoothing must not be so heavy
	# that the two converge.
	var tap := await _nudge(0.02)
	paddle.reset_swing()
	await step(3)
	var swing := await _nudge(0.12)
	assert_gt(swing, tap * 2.0, "a 6x harder swing should read as clearly faster")


func test_a_single_frame_spike_is_attenuated() -> void:
	# Raw would be delta * PHYSICS_HZ. Smoothing lerps towards that rather
	# than snapping to it, so one frame can never deliver the whole spike.
	var delta_x := 0.1
	var raw := delta_x * PHYSICS_HZ
	var speed := await _nudge(delta_x)
	assert_gt(speed, 0.0, "the spike should still move the sample")
	assert_lt(speed, raw, "a single frame should not deliver the full raw velocity")


func test_swing_speed_is_clamped() -> void:
	# A teleporting controller would otherwise hand ball.gd an enormous
	# impulse; ball.gd has no clamp of its own on this path.
	var speed := await _nudge(50.0)
	assert_lte(
		speed, paddle.max_swing_speed + 0.001, "swing speed should be clamped to max_swing_speed"
	)


func test_reset_swing_clears_the_sample() -> void:
	var speed := await _nudge(0.1)
	assert_gt(speed, 0.0, "precondition: the paddle is swinging")
	paddle.reset_swing()
	assert_eq(paddle.swing_velocity, Vector3.ZERO, "reset_swing should zero the sample")


func test_an_unknown_profile_keeps_the_exported_grip() -> void:
	paddle._apply_profile("/interaction_profiles/not/a/real/one")
	assert_eq(
		paddle.get("_grip_offset"),
		paddle.grip_offset,
		"an unknown profile should fall back to the exported offset"
	)


func test_a_known_profile_uses_its_own_grip() -> void:
	var expected: Dictionary = paddle.PROFILE_GRIPS[paddle.FRAME_CONTROLLER]
	paddle._apply_profile(paddle.FRAME_CONTROLLER)
	assert_eq(
		paddle.get("_grip_offset"),
		expected["offset"],
		"a known profile should use its own grip offset"
	)


func test_changing_grip_resets_the_swing_sample() -> void:
	# Swapping the grip offset moves the blade centre relative to the hand.
	# That displacement is not a swing and must not read as one.
	#
	# The exported fallback is moved somewhere distinctive first, because the
	# Steam Frame entry is still a placeholder equal to the Touch one (issue
	# #3) - testing against the real data would pass for the wrong reason.
	paddle.grip_offset = Vector3(1.0, 0.0, 0.0)
	paddle._apply_profile("")
	await step(2)
	var speed := await _nudge(0.1)
	assert_gt(speed, 0.0, "precondition: the paddle is swinging")

	paddle._apply_profile(paddle.FRAME_CONTROLLER)
	assert_eq(paddle.swing_velocity, Vector3.ZERO, "a grip change should reset the sample")


func test_an_unchanged_grip_does_not_reset_the_swing_sample() -> void:
	# The runtime can re-emit profile_changed with the same profile; that is
	# not a reason to throw away a swing in progress.
	var speed := await _nudge(0.1)
	assert_gt(speed, 0.0, "precondition: the paddle is swinging")
	paddle._apply_profile("")
	assert_almost_eq(
		paddle.swing_velocity.length(), speed, 0.001, "an unchanged grip should leave the sample"
	)
