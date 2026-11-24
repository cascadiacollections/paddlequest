extends GutTest

## The desktop cursor preview. It has to agree with the page: same centre,
## hidden off the page, and unable to take the click it is marking. No
## composition layer, so this runs headless.

var preview: Control


func before_each() -> void:
	preview = load("res://scenes/dev/cursor_preview.tscn").instantiate()
	add_child_autofree(preview)
	preview.track_mouse = false
	await get_tree().process_frame


func test_the_dot_sits_on_the_uv_and_ignores_the_mouse() -> void:
	var cursor: ColorRect = preview.get_node("Page/Cursor")
	assert_eq(cursor.mouse_filter, Control.MOUSE_FILTER_IGNORE, "cannot take the click")
	assert_eq(cursor.size, Vector2(XRWebPanel.CURSOR_DIAMETER_PX, XRWebPanel.CURSOR_DIAMETER_PX))

	preview.place(Vector2(0.25, 0.5))
	assert_true(cursor.visible, "on the page")
	var centre := cursor.position + cursor.size / 2.0
	assert_almost_eq(centre, Vector2(160, 180), Vector2(0.01, 0.01), "centre of a 640x360 page")


func test_the_dot_hides_off_the_page_and_when_toggled_off() -> void:
	var cursor: ColorRect = preview.get_node("Page/Cursor")
	preview.place(Vector2(1.2, 0.5))
	assert_false(cursor.visible, "past the edge")

	preview.place(Vector2(0.5, 0.5))
	assert_true(cursor.visible)
	preview.show_cursor = false
	preview.place(Vector2(0.5, 0.5))
	assert_false(cursor.visible, "the toggle hides it")


func test_a_pinned_uv_is_read_from_the_command_line() -> void:
	preview._apply_pin(PackedStringArray(["--uv=0.00,1.00"]))
	preview._apply()
	var cursor: ColorRect = preview.get_node("Page/Cursor")
	assert_true(preview._pinned)
	assert_false(preview.track_mouse)
	var centre := cursor.position + cursor.size / 2.0
	assert_almost_eq(centre, Vector2(0, 360), Vector2(0.01, 0.01), "bottom-left of the page")
