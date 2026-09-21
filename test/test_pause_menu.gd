extends PaddleTest

## The in-headset menu. Before it there was no way out of the game from
## inside the headset at all, and no recenter anywhere in the project.

var menu: Node3D
var origin: XROrigin3D


func before_each() -> void:
	await build_scene()
	menu = main.get_node("PauseMenu")
	origin = main.get_node("XROrigin3D")
	await await_serve()


func test_it_starts_closed_and_hidden() -> void:
	assert_false(menu.is_open(), "the menu should not be in the way at startup")
	assert_false(menu.visible, "and should not be drawn")


func test_toggling_opens_and_closes_it() -> void:
	menu.toggle()
	assert_true(menu.is_open(), "toggle should open it")
	assert_true(menu.visible, "and show it")

	menu.toggle()
	assert_false(menu.is_open(), "toggle again should close it")
	assert_false(menu.visible, "and hide it")


func test_opening_suspends_the_rally_without_pausing_the_tree() -> void:
	# get_tree().paused would take XRCamera3D with it and lock the rendered
	# world to the player's head, which is the fastest way to make someone
	# ill. Gameplay stops; tracking must not.
	menu.open()
	await step(2)

	assert_true(ball.freeze, "the ball should be held while paused")
	assert_false(get_tree().paused, "the scene tree must keep running")


func test_closing_resumes_the_rally() -> void:
	menu.open()
	await step(2)
	menu.close()
	await step(2)

	assert_false(ball.freeze, "the ball should be released again")
	assert_false(menu.visible, "and the panel put away")


func test_locomotion_is_locked_while_the_menu_is_open() -> void:
	# The menu navigates with the same thumbstick locomotion strafes with.
	menu.open()
	await step(2)
	assert_true(origin.get("_locked"), "locomotion should be locked")

	menu.close()
	await step(2)
	assert_false(origin.get("_locked"), "and released on close")


func test_the_stick_moves_the_selection_and_wraps() -> void:
	menu.open()
	assert_eq(menu.selected_item(), menu.RESUME, "it should open on Resume")

	menu._move_selection(1)
	assert_eq(menu.selected_item(), menu.RECENTER, "down should step one row")

	menu._move_selection(-1)
	assert_eq(menu.selected_item(), menu.RESUME, "and up should step back")

	menu._move_selection(-1)
	assert_eq(menu.selected_item(), menu.QUIT, "going up from the top should wrap")


func test_resume_closes_the_menu() -> void:
	menu.open()
	while menu.selected_item() != menu.RESUME:
		menu._move_selection(1)
	menu.activate()
	assert_false(menu.is_open(), "activating Resume should close the menu")


func test_a_toggle_row_flips_and_persists_the_setting() -> void:
	menu.open()
	while menu.selected_item() != menu.SNAP_TURN:
		menu._move_selection(1)

	var before: bool = SaveGame.load_setting("snap_turn")
	menu.activate()
	var after: bool = SaveGame.load_setting("snap_turn")

	assert_ne(before, after, "activating a toggle row should flip the setting")
	assert_true(menu.is_open(), "and should not close the menu")


func test_a_toggle_takes_effect_immediately() -> void:
	# A comfort toggle you cannot feel the effect of is one you cannot judge.
	menu.open()
	while menu.selected_item() != menu.SNAP_TURN:
		menu._move_selection(1)

	menu.activate()
	await step(1)
	assert_eq(
		origin.get("_snap_turn"),
		SaveGame.load_setting("snap_turn"),
		"locomotion should already be running the new setting"
	)


func test_the_panel_shows_every_row_and_marks_the_selection() -> void:
	menu.open()
	var label: Label3D = menu.get_node("Label")
	for key in menu.ITEMS:
		assert_string_contains(label.text, menu.LABELS[key], "row '%s' should be listed" % key)
	assert_string_contains(label.text, "> ", "the selected row should be marked")


func test_the_panel_lands_in_front_of_the_player() -> void:
	var camera: XRCamera3D = main.get_node("XROrigin3D/XRCamera3D")
	menu.open()
	await step(1)

	var to_menu := menu.global_position - camera.global_position
	assert_almost_eq(to_menu.length(), menu.distance, 0.05, "at the configured distance")

	var forward := -camera.global_transform.basis.z
	forward.y = 0.0
	assert_gt(to_menu.normalized().dot(forward.normalized()), 0.9, "and in front, not behind")
