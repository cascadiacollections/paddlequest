extends GutTest

## The action map is the only place the game knows about a specific headset's
## controllers. A profile that is missing here does not fail loudly - OpenXR
## just never suggests those bindings and the buttons quietly do nothing on
## that device, which is the sort of thing you discover wearing the headset.

const ACTION_MAP := "res://openxr_action_map.tres"
const PaddleScript := preload("res://scripts/paddle.gd")

const TOUCH := "/interaction_profiles/oculus/touch_controller"
const FRAME := "/interaction_profiles/valve/frame_controller_valve"
const GENERIC := "/interaction_profiles/khr/generic_controller"

## Actions game.gd and paddle.gd actually consume. Everything else in the map
## is there for completeness; these are load-bearing.
const REQUIRED_ACTIONS := ["primary", "ax_button", "by_button", "menu_button", "haptic"]


func _map() -> OpenXRActionMap:
	var map: OpenXRActionMap = load(ACTION_MAP)
	assert_not_null(map, "action map should load")
	return map


func _profile_paths(map: OpenXRActionMap) -> Array[String]:
	var paths: Array[String] = []
	for i in map.get_interaction_profile_count():
		paths.append(map.get_interaction_profile(i).interaction_profile_path)
	return paths


func test_ships_profiles_for_every_headset_we_target() -> void:
	var paths := _profile_paths(_map())
	for required in [TOUCH, FRAME, GENERIC]:
		assert_true(
			paths.has(required), "%s missing from the action map (have: %s)" % [required, paths]
		)


func test_steam_frame_binds_the_actions_the_game_reads() -> void:
	var map := _map()
	var profile: OpenXRInteractionProfile = null
	for i in map.get_interaction_profile_count():
		var candidate := map.get_interaction_profile(i)
		if candidate.interaction_profile_path == FRAME:
			profile = candidate
			break
	assert_not_null(profile, "Steam Frame profile should be present")
	if profile == null:
		return

	var bound: Array[String] = []
	for binding in profile.bindings:
		if binding.action != null and not bound.has(binding.action.resource_name):
			bound.append(binding.action.resource_name)

	for action in REQUIRED_ACTIONS:
		assert_true(
			bound.has(action), "'%s' is unbound on Steam Frame (bound: %s)" % [action, bound]
		)


func test_paddle_grip_overrides_name_profiles_that_exist() -> void:
	# paddle.gd keys its per-device grip geometry on the interaction profile
	# string. A typo there is invisible: the lookup just misses and the paddle
	# silently keeps the Touch offset on every headset.
	var paths := _profile_paths(_map())
	for profile: String in PaddleScript.PROFILE_GRIPS:
		assert_true(
			paths.has(profile),
			"paddle.gd has a grip override for '%s', which is not in the action map" % profile
		)


func test_steam_frame_binding_paths_are_well_formed() -> void:
	# Frame puts the face buttons on the right controller and a dpad on the
	# left. An unregistered path is dropped silently by the runtime, so at
	# minimum assert the shape and that nothing reaches for a left-hand
	# A/B/X/Y that does not exist on this device.
	var map := _map()
	for i in map.get_interaction_profile_count():
		var profile := map.get_interaction_profile(i)
		if profile.interaction_profile_path != FRAME:
			continue
		for binding in profile.bindings:
			var path: String = binding.binding_path
			assert_true(
				path.begins_with("/user/hand/left/") or path.begins_with("/user/hand/right/"),
				"unexpected top level path: %s" % path
			)
			for face in ["/input/a/", "/input/b/", "/input/x/", "/input/y/", "/input/menu/"]:
				assert_false(
					path.begins_with("/user/hand/left") and path.contains(face),
					"%s does not exist on the Steam Frame left controller" % path
				)
