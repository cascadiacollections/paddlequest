extends PaddleTest

## Panel placement and the respawn cycle. test_scoring.gd already covers the
## game-level path (overlapping a panel scores, a dark one does not score
## again); this covers targets.gd's own invariants, which are geometric and
## were previously untested and unseeded.

const TargetsScript := preload("res://scripts/targets.gd")

var targets: Node3D


func before_each() -> void:
	await build_scene()
	targets = main.get_node("Targets")


func _panels() -> Array[Area3D]:
	var found: Array[Area3D] = []
	for child in targets.get_children():
		var area := child as Area3D
		if area != null:
			found.append(area)
	return found


func test_the_bands_do_not_overlap() -> void:
	# The bands are what stop two panels landing on top of each other, so
	# they have to be disjoint before anything else here means much.
	var bands := TargetsScript.BANDS
	for i in range(bands.size()):
		assert_lt(bands[i].x, bands[i].y, "band %d should be non-empty" % i)
		if i > 0:
			assert_gte(
				bands[i].x, bands[i - 1].y, "band %d should start after band %d ends" % [i, i - 1]
			)


func test_every_panel_starts_inside_its_own_band() -> void:
	var panels := _panels()
	assert_eq(panels.size(), 3, "the wall should have three panels")
	for i in range(panels.size()):
		var band: Vector2 = TargetsScript.BANDS[i % TargetsScript.BANDS.size()]
		var x := panels[i].position.x
		assert_between(x, band.x, band.y, "panel %d should sit inside its band" % i)


func test_every_panel_starts_at_rally_height() -> void:
	# Panels above this band are out of the headset's field of view while you
	# are watching the ball, which is the whole reason the range exists.
	for i in range(_panels().size()):
		var y := _panels()[i].position.y
		assert_between(y, targets.height_range.x, targets.height_range.y, "panel %d height" % i)


func test_a_struck_panel_goes_dark_and_stops_monitoring() -> void:
	var panel := _panels()[0]
	assert_true(panel.monitoring, "precondition: the panel is live")

	var hits := []
	targets.target_hit.connect(func(bonus: int): hits.append(bonus))
	panel.body_entered.emit(ball)
	await step(2)

	assert_eq(hits, [targets.bonus], "a hit should award exactly one bonus")
	assert_false(panel.visible, "a struck panel should go dark")
	assert_false(panel.monitoring, "a struck panel should stop detecting")


func test_a_dark_panel_cannot_be_struck_again() -> void:
	var panel := _panels()[0]
	var hits := []
	targets.target_hit.connect(func(bonus: int): hits.append(bonus))

	panel.body_entered.emit(ball)
	await step(2)
	panel.body_entered.emit(ball)
	await step(2)

	assert_eq(hits.size(), 1, "a dark panel should not score a second time")


func test_only_a_rigid_body_counts() -> void:
	var panel := _panels()[0]
	var hits := []
	targets.target_hit.connect(func(bonus: int): hits.append(bonus))

	var not_the_ball := Area3D.new()
	add_child_autofree(not_the_ball)
	panel.body_entered.emit(not_the_ball)
	await step(2)

	assert_eq(hits, [], "only the ball should score")
	assert_true(panel.monitoring, "a non-ball overlap should leave the panel live")


func test_a_panel_comes_back_inside_its_own_band() -> void:
	targets.respawn_delay = 0.05
	var panel := _panels()[0]
	var band: Vector2 = TargetsScript.BANDS[0]

	panel.body_entered.emit(ball)
	await step(2)
	assert_false(panel.visible, "precondition: the panel is dark")

	# The respawn is a SceneTreeTimer in wall time, not physics frames.
	await get_tree().create_timer(0.3).timeout
	await step(2)

	assert_true(panel.visible, "the panel should come back")
	assert_true(panel.monitoring, "and start detecting again")
	assert_between(panel.position.x, band.x, band.y, "it should stay in its own band")
	assert_between(
		panel.position.y, targets.height_range.x, targets.height_range.y, "and at rally height"
	)


func test_the_same_seed_places_panels_the_same_way() -> void:
	# Unseeded placement is what a player should get, but it made every
	# assertion above probabilistic. rng_seed makes it reproducible.
	var first: Array = await _seeded_positions(1234)
	var second: Array = await _seeded_positions(1234)
	var different: Array = await _seeded_positions(99)

	assert_eq(first, second, "the same seed should place panels identically")
	assert_ne(first, different, "a different seed should place them differently")


## Build a Targets node of its own with `seed` and report where its panels
## landed. Done by hand rather than through the scene so the seed can be set
## before _ready runs.
func _seeded_positions(rng_seed: int) -> Array:
	var node := Node3D.new()
	node.set_script(TargetsScript)
	node.rng_seed = rng_seed
	for i in 3:
		node.add_child(Area3D.new())
	add_child_autofree(node)
	await step(1)

	var positions := []
	for child in node.get_children():
		var area := child as Area3D
		if area != null:
			positions.append(Vector2(area.position.x, area.position.y))
	return positions
