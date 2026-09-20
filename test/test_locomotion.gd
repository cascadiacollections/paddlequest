extends PaddleTest

## The XR origin is not a physics body, so nothing stops it walking through a
## wall except the clamp in locomotion.gd.

func before_each() -> void:
	await build_scene()


func test_strafing_is_clamped_inside_the_court() -> void:
	var origin: XROrigin3D = main.get_node("XROrigin3D")
	var camera: XRCamera3D = origin.get_node("XRCamera3D")

	# Drive far past the side wall in one go.
	origin._move(1.0, 0.0, 30.0)
	await step(2)

	assert_lte(
		camera.global_position.x, origin.bounds_max.x + 0.01,
		"the player should not cross the right wall"
	)

	origin._move(-1.0, 0.0, 30.0)
	await step(2)
	assert_gte(
		camera.global_position.x, origin.bounds_min.x - 0.01,
		"the player should not cross the left wall"
	)


func test_crouching_lowers_the_origin_and_recovers() -> void:
	var origin: XROrigin3D = main.get_node("XROrigin3D")
	var standing := origin.position.y

	origin._crouch_toward(-1.0, 1.0)
	assert_lt(origin.position.y, standing, "stick down should crouch")

	origin._crouch_toward(1.0, 1.0)
	assert_almost_eq(origin.position.y, standing, 0.01, "stick up should stand")
