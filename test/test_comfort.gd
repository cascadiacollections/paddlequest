extends PaddleTest

## Comfort options. Tunnelling and snap turn are the two levers that decide
## whether some people can play this at all, so the defaults matter as much
## as the mechanics: both are on unless someone turns them off.

const SaveGameScript := preload("res://scripts/save_game.gd")

var origin: XROrigin3D
var vignette: MeshInstance3D


func before_each() -> void:
	await build_scene()
	origin = main.get_node("XROrigin3D")
	vignette = main.get_node("XROrigin3D/XRCamera3D/Vignette")


func test_the_comfortable_settings_are_the_defaults() -> void:
	# Someone who needs tunnelling should not have to find the menu first.
	assert_true(SaveGameScript.DEFAULTS["comfort_vignette"], "vignette on by default")
	assert_true(SaveGameScript.DEFAULTS["snap_turn"], "snap turn on by default")
	assert_false(SaveGameScript.DEFAULTS["seated"], "standing by default")


func test_the_vignette_starts_open_and_invisible() -> void:
	assert_false(vignette.visible, "nothing should be drawn while standing still")


func test_the_vignette_closes_in_while_moving_and_opens_after() -> void:
	origin.motion_changed.emit(true)
	await wait_seconds(0.3)
	assert_true(vignette.visible, "the vignette should close in under motion")
	var closed: float = vignette.get("_amount")
	assert_gt(closed, 0.5, "and should be most of the way in")

	origin.motion_changed.emit(false)
	await wait_seconds(0.6)
	assert_lt(vignette.get("_amount"), closed, "and should open back up when motion stops")


func test_the_vignette_stays_open_when_switched_off() -> void:
	vignette.set("_enabled", false)
	origin.motion_changed.emit(true)
	await wait_seconds(0.3)
	assert_false(vignette.visible, "a disabled vignette should never draw")


func test_snap_turn_rotates_by_one_step_per_push() -> void:
	origin.set("_snap_turn", true)
	var before := origin.global_rotation.y

	# Held, not tapped: a snap turn should fire once and then wait for the
	# stick to come back to centre.
	origin._turn(1.0, 0.016)
	origin._turn(1.0, 0.016)
	origin._turn(1.0, 0.016)

	var step := absf(wrapf(origin.global_rotation.y - before, -PI, PI))
	assert_almost_eq(
		rad_to_deg(step), origin.snap_turn_degrees, 0.5, "one push should be exactly one step"
	)


func test_snap_turn_rearms_when_the_stick_centres() -> void:
	origin.set("_snap_turn", true)
	var before := origin.global_rotation.y

	origin._turn(1.0, 0.016)
	origin._turn(0.0, 0.016)
	origin._turn(1.0, 0.016)

	var turned := absf(wrapf(origin.global_rotation.y - before, -PI, PI))
	assert_almost_eq(
		rad_to_deg(turned),
		origin.snap_turn_degrees * 2.0,
		0.5,
		"centring the stick should allow a second step"
	)


func test_turning_right_and_left_cancel_out() -> void:
	origin.set("_snap_turn", true)
	var before := origin.global_rotation.y

	origin._turn(1.0, 0.016)
	origin._turn(0.0, 0.016)
	origin._turn(-1.0, 0.016)

	var net := absf(wrapf(origin.global_rotation.y - before, -PI, PI))
	assert_almost_eq(rad_to_deg(net), 0.0, 0.5, "opposite turns should cancel")


func test_turning_pivots_about_the_head_not_the_origin() -> void:
	# In roomscale the head and the origin can be a metre apart. Turning
	# about the origin swings the player through an arc instead of rotating
	# them in place, which is both wrong and nauseating.
	var camera: XRCamera3D = main.get_node("XROrigin3D/XRCamera3D")
	camera.position = Vector3(1.0, 1.6, 0.0)
	await step(1)

	var head_before := camera.global_position
	origin.set("_snap_turn", true)
	origin._turn(1.0, 0.016)
	await step(1)

	assert_almost_eq(
		camera.global_position.distance_to(head_before), 0.0, 0.01, "the head should stay put"
	)


func test_seated_mode_lowers_the_origin() -> void:
	var standing := origin.position.y
	origin.set_seated(true)
	await step(3)
	assert_almost_eq(
		origin.position.y, standing - origin.seated_drop, 0.01, "seated should drop the origin"
	)

	origin.set_seated(false)
	await step(3)
	assert_almost_eq(origin.position.y, standing, 0.01, "and standing should put it back")
