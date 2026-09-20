extends PaddleTest

## Wall targets and the miss/reset cycle.

func before_each() -> void:
	await build_scene()
	await await_serve()


func test_hitting_a_target_scores_points() -> void:
	var target: Area3D = main.get_node("Targets").get_child(0)
	var before := points()
	assert_eq(before, 0, "no points before anything is hit")

	# Park the ball inside the panel; detection is an overlap, not a collision.
	ball.linear_velocity = Vector3.ZERO
	ball.global_position = target.global_position
	await step(10)

	assert_gt(points(), before, "overlapping a target panel should score")


func test_a_struck_target_stops_scoring_until_it_reappears() -> void:
	var target: Area3D = main.get_node("Targets").get_child(0)
	ball.linear_velocity = Vector3.ZERO
	ball.global_position = target.global_position
	await step(10)

	var after_first := points()
	await step(10)
	assert_eq(points(), after_first, "a dark target should not score again")


func test_reaching_the_miss_zone_resets_the_rally() -> void:
	ball.linear_velocity = Vector3.ZERO
	ball.global_position = (main.get_node("MissZone") as Area3D).global_position
	await step(10)
	assert_string_contains(label_text(), "Miss", "missing should be announced")
