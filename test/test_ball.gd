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


func test_a_harder_impact_is_louder_and_higher() -> void:
	# Pitch and volume both ride the impact speed; if either inverted, a
	# hard smash would sound like a tap and nobody would notice in a diff.
	assert_gt(ball._impact_pitch(12.0), ball._impact_pitch(2.0), "harder should be higher")
	assert_gt(ball._impact_volume_db(12.0), ball._impact_volume_db(2.0), "harder should be louder")


func test_each_surface_has_its_own_voice() -> void:
	# If two voices collapse onto the same sample, pitch and level, a paddle
	# hit and a floor bounce become the same event to the ear, which is the
	# thing this exists to avoid.
	var voices: Dictionary = ball.VOICES
	for key in ["paddle", "front_wall", "floor", "other"]:
		assert_true(voices.has(key), "missing a voice for '%s'" % key)

	var seen := []
	for key in voices:
		var tone: Dictionary = voices[key]
		assert_true(tone["stream"] is AudioStreamWAV, "'%s' has no sample" % key)
		var signature := [tone["stream"].resource_path, tone["pitch"], tone["db"]]
		assert_false(seen.has(signature), "'%s' duplicates another voice" % key)
		seen.append(signature)

	# The three events the player should tell apart with their eyes shut get
	# three different samples, not one sample voiced three ways.
	var paths := {}
	for key in ["paddle", "front_wall", "floor"]:
		paths[voices[key]["stream"].resource_path] = key
	assert_eq(paths.size(), 3, "paddle, front wall and floor should each have their own sample")

	assert_lt(voices["floor"]["db"], voices["paddle"]["db"], "floor bounces should sit back")
	assert_lt(voices["other"]["db"], voices["paddle"]["db"], "incidental bounces should sit back")


func test_jitter_never_outweighs_impact_speed() -> void:
	# The per-hit spread is there to stop retriggering sounding mechanical.
	# If it grew past the gap between a soft and a hard hit, speed would stop
	# being audible, so keep it well inside that gap.
	var soft: float = ball._impact_pitch(4.0) * (1.0 + ball.PITCH_JITTER)
	var hard: float = ball._impact_pitch(12.0) * (1.0 - ball.PITCH_JITTER)
	assert_lt(soft, hard, "pitch jitter should not let a soft hit outrank a hard one")


func test_the_floor_is_tagged_for_its_own_voice() -> void:
	var floor_body := main.get_node("Court/Floor")
	assert_true(floor_body.is_in_group("floor"), "the floor must be in the 'floor' group")
