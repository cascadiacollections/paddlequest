extends PaddleTest

## A ball bouncing straight up and down reaches neither the front wall nor the
## miss zone, so the rally could neither score nor end and the game wedged.

func before_each() -> void:
	await build_scene()
	await await_first_wall_hit()


func test_a_vertical_ball_is_pushed_back_into_play() -> void:
	ball.global_position = Vector3(0.0, 2.0, -3.0)
	ball.linear_velocity = Vector3(0.0, 6.0, 0.0)
	await step(30)

	var horizontal := Vector2(ball.linear_velocity.x, ball.linear_velocity.z).length()
	assert_gt(
		horizontal, 0.5,
		"a near-vertical ball should be steered back towards the wall"
	)


func test_speed_is_capped() -> void:
	ball.linear_velocity = Vector3(0.0, 0.0, -500.0)
	await step(10)
	assert_lte(
		ball.linear_velocity.length(), ball.max_speed * 1.1,
		"ball speed should be clamped to max_speed"
	)


func test_ball_keeps_moving_once_in_play() -> void:
	ball.global_position = Vector3(0.0, 1.3, -3.0)
	ball.linear_velocity = Vector3(0.0, 0.0, -0.2)
	await step(30)
	assert_gte(
		ball.linear_velocity.length(), ball.min_speed * 0.8,
		"the speed floor should keep a slow rally alive"
	)
