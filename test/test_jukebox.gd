extends PaddleTest

## The compositor-backed web panel. Everything that touches Android is
## unreachable from a headless Linux run, so what is covered here is the part
## that decides whether the panel is allowed to go somewhere - which is the
## part a mistake in is a store rejection rather than a black quad - plus the
## promise that the node stays completely inert off-device.

var jukebox: Jukebox


func before_each() -> void:
	await build_scene()
	jukebox = main.get_node("XROrigin3D/Jukebox")


func test_the_panel_is_inert_off_device() -> void:
	# There is no Surface to fill on the desktop. Asking OpenXR for a swapchain
	# nothing writes to would leave a quad of undefined memory in the scene.
	assert_false(jukebox.use_android_surface, "no android surface off-device")
	assert_false(jukebox.visible, "and nothing drawn")
	assert_false(jukebox.is_live(), "and no web view")


func test_the_scene_sizes_the_surface_before_it_asks_for_one() -> void:
	# OpenXRCompositionLayer.set_android_surface_size() takes a different path
	# once use_android_surface is already true: it calls xrUpdateSwapchainFB on
	# a swapchain that has not been created yet, which fails at session start
	# with XR_ERROR_HANDLE_INVALID. Setting the size first skips that call
	# entirely. Read as text because the order of the two lines is the whole
	# point and a loaded scene has already lost it.
	var scene := FileAccess.get_file_as_string("res://scenes/main.tscn")
	var size_at := scene.find("android_surface_size")
	var use_at := scene.find("use_android_surface")
	assert_gt(size_at, -1, "the scene should set android_surface_size")
	assert_gt(use_at, -1, "and use_android_surface")
	assert_lt(size_at, use_at, "size must come first or the swapchain call fires early")


func test_the_probe_page_needs_nothing_the_panel_cannot_do() -> void:
	# The probe exists to isolate the surface, so it must not depend on the
	# settings that cannot be applied (JavaScript) or on the network.
	assert_false(Jukebox.PROBE_HTML.contains("<script"), "no JavaScript")
	assert_false(Jukebox.PROBE_HTML.contains("http"), "nothing fetched")
	assert_true(Jukebox.PROBE_HTML.contains("TOP LEFT"), "a marker to read the flip from")
	assert_true(Jukebox.PROBE_HTML.contains("BOTTOM RIGHT"), "and one to read it against")


func test_the_home_url_is_one_the_allowlist_admits() -> void:
	# A default that the node's own allowlist refuses is a panel that ships
	# blank, and the warning for it only appears on a headset.
	assert_true(
		Jukebox.is_allowed(jukebox.home_url, jukebox.allowed_hosts),
		"home_url should pass the allowlist it ships with"
	)


func test_a_refused_url_is_reported_and_not_loaded() -> void:
	watch_signals(jukebox)
	var accepted: bool = jukebox.load_url("https://example.com/")
	assert_false(accepted, "an off-list host should be refused")

	# The signal is deferred, because load_url can be reached from the Android
	# UI thread and emit() is rejected off the Godot one. The return value is
	# immediate; the signal is not.
	assert_signal_not_emitted(jukebox, "navigation_blocked", "not in the same frame")
	await step(1)
	assert_signal_emitted(jukebox, "navigation_blocked", "but on the next one")


func test_an_allowed_url_is_accepted_even_before_the_surface_exists() -> void:
	# Held rather than dropped: the surface does not exist until the OpenXR
	# session begins, which is long after anything would want to set a station.
	assert_true(jukebox.load_url("https://music.youtube.com/"), "should be accepted")


func test_the_host_is_read_out_of_whatever_shape_the_url_is_in() -> void:
	assert_eq(Jukebox.host_of("https://youtube.com"), "youtube.com", "bare host")
	assert_eq(Jukebox.host_of("https://YouTube.COM/watch?v=1"), "youtube.com", "case and path")
	assert_eq(Jukebox.host_of("https://youtube.com:8443/x"), "youtube.com", "port")
	assert_eq(Jukebox.host_of("https://youtube.com#frag"), "youtube.com", "fragment")
	assert_eq(Jukebox.host_of("https://[::1]:8080/x"), "[::1]", "ipv6 literal keeps its colons")


func test_a_subdomain_of_an_allowed_host_is_allowed() -> void:
	var hosts := PackedStringArray(["youtube.com"])
	assert_true(Jukebox.is_allowed("https://music.youtube.com/", hosts), "subdomain")
	assert_true(Jukebox.is_allowed("https://youtube.com/", hosts), "the host itself")


func test_a_lookalike_host_is_not_allowed() -> void:
	# The suffix match has to land on a dot. Without that, every one of these
	# reads as YouTube, and an allowlist that accepts notyoutube.com is not one.
	var hosts := PackedStringArray(["youtube.com"])
	assert_false(Jukebox.is_allowed("https://notyoutube.com/", hosts), "no dot boundary")
	assert_false(Jukebox.is_allowed("https://youtube.com.evil.example/", hosts), "suffixed")
	assert_false(Jukebox.is_allowed("https://evil.example/?x=youtube.com", hosts), "in a query")


func test_credentials_cannot_disguise_the_host() -> void:
	# https://youtube.com@evil.example/ goes to evil.example. Splitting on the
	# first '@' instead of the last is the classic way to get this wrong.
	var hosts := PackedStringArray(["youtube.com"])
	assert_false(Jukebox.is_allowed("https://youtube.com@evil.example/", hosts), "userinfo")
	assert_false(Jukebox.is_allowed("https://a@youtube.com@evil.example/", hosts), "twice over")


func test_only_https_is_allowed() -> void:
	# file:// and content:// reach our own save data; javascript: runs in
	# whatever is already loaded. None of them are a music service.
	var hosts := PackedStringArray(["youtube.com"])
	assert_false(Jukebox.is_allowed("http://youtube.com/", hosts), "plain http")
	assert_false(Jukebox.is_allowed("file:///data/data/x/files/save.cfg", hosts), "file")
	assert_false(Jukebox.is_allowed("javascript:alert(1)", hosts), "javascript")
	assert_true(Jukebox.is_allowed("  HTTPS://youtube.com/  ", hosts), "padded https still passes")


func test_an_empty_allowlist_admits_nothing() -> void:
	# Fail-closed. A panel that quietly becomes an open browser when someone
	# clears the field is the failure this ordering exists to prevent.
	assert_false(Jukebox.is_allowed("https://youtube.com/", PackedStringArray()), "nothing")


func test_the_vertical_flip_workaround_matches_the_runtime() -> void:
	# XR_KHR_android_surface_swapchain is implemented inconsistently: Oculus
	# flips under GL, Pico flips under Vulkan. Assuming either is the rule
	# gets the panel upside down on the other one.
	assert_true(Jukebox.needs_vertical_flip("Oculus", "opengl3"), "Oculus on GL")
	assert_true(Jukebox.needs_vertical_flip("Oculus", "opengl3_es"), "Oculus on GLES")
	assert_false(Jukebox.needs_vertical_flip("Oculus", "vulkan"), "Oculus on Vulkan")
	assert_true(Jukebox.needs_vertical_flip("Pico", "vulkan"), "Pico on Vulkan")
	assert_false(Jukebox.needs_vertical_flip("Pico", "opengl3"), "Pico on GL")
	assert_false(Jukebox.needs_vertical_flip("SteamVR/OpenXR", "vulkan"), "anything else")


func test_this_project_ships_the_combination_that_does_not_flip() -> void:
	# Quest plus the mobile (Vulkan) renderer, which project.godot pins. If
	# either ever changes, the panel comes up upside down and this says why.
	assert_false(Jukebox.needs_vertical_flip("Oculus", "vulkan"), "Quest on Vulkan is upright")
	assert_eq(
		ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile"),
		"mobile",
		"the mobile renderer is Vulkan on Quest"
	)
