extends PaddleTest

## The serve used to be aimed straight at WallTarget, ignoring gravity. The ball
## dropped most of a metre crossing the court and arrived around knee height,
## which put the whole rally below the player's field of view and out of reach
## of the wall targets.

func before_each() -> void:
	await build_scene()


func test_serve_arrives_at_the_wall_near_the_aim_point() -> void:
	var target: Marker3D = main.get_node("WallTarget")

	var reached := await step_until(
		func(): return ball.global_position.z <= WALL_Z, seconds(6.0)
	)
	assert_true(reached, "ball should reach the front wall within six seconds")

	assert_almost_eq(
		ball.global_position.y, target.global_position.y, 0.35,
		"serve should arrive near WallTarget rather than sagging"
	)


func test_serve_travels_towards_the_wall() -> void:
	await step_until(func(): return ball.linear_velocity.length() > 0.1, seconds(3.0))
	assert_lt(
		ball.linear_velocity.z, 0.0,
		"the serve should head towards the front wall, which is at -Z"
	)
