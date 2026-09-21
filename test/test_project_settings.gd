extends GutTest

## project.godot is ConfigFile format: comments are ';', and a '#' line makes
## Godot silently discard every setting after it in that section. That cost us
## a working startup_alert and both foveation settings, with no error anywhere.

func test_project_godot_has_no_hash_comments() -> void:
	var file := FileAccess.open("res://project.godot", FileAccess.READ)
	assert_not_null(file, "project.godot should be readable")

	var line_number := 0
	var offenders: Array[String] = []
	while not file.eof_reached():
		line_number += 1
		var line := file.get_line().strip_edges()
		if line.begins_with("#"):
			offenders.append("line %d: %s" % [line_number, line])
	file.close()

	assert_eq(
		offenders, [] as Array[String],
		"'#' comments silently void the rest of their section; use ';'"
	)


func test_settings_that_a_broken_comment_would_have_swallowed() -> void:
	assert_false(
		ProjectSettings.get_setting("xr/openxr/startup_alert"),
		"startup_alert must be off or desktop runs block on a modal"
	)
	assert_eq(
		ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		"mobile", "Quest needs the mobile renderer"
	)
	assert_true(
		ProjectSettings.get_setting("xr/openxr/enabled"),
		"OpenXR must be enabled"
	)


func test_physics_interpolation_is_on() -> void:
	# Physics is 90Hz; headsets render at 72 through 144. Without
	# interpolation the ball and paddle step at the physics rate on any
	# headset that is not also 90Hz.
	assert_true(
		ProjectSettings.get_setting("physics/common/physics_interpolation"),
		"physics interpolation decouples the 90Hz tick from the display rate"
	)
	assert_eq(
		ProjectSettings.get_setting("physics/common/physics_ticks_per_second"),
		90,
		"test_helpers.PHYSICS_HZ assumes 90; change both together"
	)
