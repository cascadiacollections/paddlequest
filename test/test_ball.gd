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
	assert_gt(horizontal, 0.5, "a near-vertical ball should be steered back towards the wall")


func test_speed_is_capped() -> void:
	ball.linear_velocity = Vector3(0.0, 0.0, -500.0)
	await step(10)
	assert_lte(
		ball.linear_velocity.length(),
		ball.absolute_max_speed * 1.1,
		"ball speed should never exceed the hard ceiling"
	)


func test_the_rally_ceiling_resets_on_a_serve() -> void:
	# The ceiling climbs by rally_gain off the front wall. It used to live in
	# the same @export as the authored value, reset by a literal 16.0 in
	# game.gd - so editing the export in the inspector silently did nothing.
	var raised := await step_until(
		func(): return ball.get("_max_speed") > ball.base_max_speed, seconds(8.0)
	)
	assert_true(raised, "the ceiling should climb during a rally")

	ball.serve(Vector3(0.0, 1.25, 1.5), Vector3(0.0, 1.25, WALL_Z))
	assert_almost_eq(
		ball.get("_max_speed"),
		ball.base_max_speed,
		0.001,
		"a serve should put the ceiling back to the authored value"
	)


func test_ball_keeps_moving_once_in_play() -> void:
	ball.global_position = Vector3(0.0, 1.3, -3.0)
	ball.linear_velocity = Vector3(0.0, 0.0, -0.2)
	await step(30)
	assert_gte(
		ball.linear_velocity.length(),
		ball.min_speed * 0.8,
		"the speed floor should keep a slow rally alive"
	)
