extends GutTest

## The reusable panel in addons/xr_webview.
##
## Everything that touches Android is unreachable from a headless Linux run, so
## what is covered here is the arithmetic between a raycast and a touch event -
## which is the part that fails quietly, by putting the press somewhere other
## than where the ray was pointing, rather than by throwing.

const QUAD := Vector2(1.28, 0.72)

var panel: XRWebPanel


func before_each() -> void:
	# Never enters the tree: _ready() would ask for an OpenXR interface, and
	# none of this needs one.
	panel = XRWebPanel.new()
	panel.quad_size = QUAD


func after_each() -> void:
	panel.free()


func test_the_centre_of_the_quad_is_the_centre_of_the_page() -> void:
	assert_eq(panel.local_to_uv(Vector3.ZERO), Vector2(0.5, 0.5), "dead centre")


func test_the_corners_map_to_the_corners() -> void:
	# The quad is centred on its origin, so its corners are at half extents.
	var top_left := Vector3(-QUAD.x / 2.0, QUAD.y / 2.0, 0.0)
	var bottom_right := Vector3(QUAD.x / 2.0, -QUAD.y / 2.0, 0.0)
	assert_eq(panel.local_to_uv(top_left), Vector2(0.0, 0.0), "top left of the page")
	assert_eq(panel.local_to_uv(bottom_right), Vector2(1.0, 1.0), "bottom right")


func test_the_vertical_axis_is_flipped() -> void:
	# 3D y grows upward and page y grows downward. Getting this backwards puts
	# every press in the mirror image of where the ray pointed, which looks
	# like a working panel that ignores what you aim at.
	var above_centre := Vector3(0.0, QUAD.y / 4.0, 0.0)
	assert_lt(panel.local_to_uv(above_centre).y, 0.5, "higher up the quad is nearer the top")


func test_a_point_off_the_panel_is_off_the_panel() -> void:
	# Refused rather than clamped: a ray that has slid off the edge should end
	# the gesture, not pin it to the border and keep dragging.
	assert_true(XRWebPanel.uv_is_on_panel(Vector2(0.5, 0.5)), "the middle")
	assert_true(XRWebPanel.uv_is_on_panel(Vector2(0.0, 1.0)), "the edge counts as on")
	assert_false(XRWebPanel.uv_is_on_panel(Vector2(-0.01, 0.5)), "past the left")
	assert_false(XRWebPanel.uv_is_on_panel(Vector2(0.5, 1.01)), "past the bottom")

	var beyond := Vector3(QUAD.x, 0.0, 0.0)
	assert_false(XRWebPanel.uv_is_on_panel(panel.local_to_uv(beyond)), "a ray past the edge")


func test_a_touch_goes_nowhere_without_a_web_view() -> void:
	# Off-device there is no WebView to dispatch to, and send_touch() has to
	# say so rather than reaching for a null Java object.
	assert_false(panel.is_live(), "no web view off-device")
	assert_false(panel.send_touch(XRWebPanel.ACTION_DOWN, Vector2(0.5, 0.5)), "so no touch")
	assert_false(panel.tap(Vector2(0.5, 0.5)), "and no tap")


func test_a_hit_maps_to_the_surface_pixel_the_touch_lands_on() -> void:
	# The corners are the first and last pixel edges, not one past them.
	var size := Vector2i(1280, 720)
	assert_eq(XRWebPanel.uv_to_surface_px(Vector2(0.0, 0.0), size), Vector2(0, 0), "top left")
	assert_eq(XRWebPanel.uv_to_surface_px(Vector2(1.0, 1.0), size), Vector2(1280, 720), "far edge")
	assert_eq(XRWebPanel.uv_to_surface_px(Vector2(0.5, 0.5), size), Vector2(640, 360), "centre")


func test_the_mapping_follows_the_panel_aspect_not_a_square() -> void:
	# A wide, short quad on a surface of the same aspect. A mapping that
	# divided both axes by one extent would put this hit at the wrong height.
	panel.quad_size = Vector2(2.0, 0.5)
	var hit := Vector3(0.5, 0.125, 0.0)  # right of centre by a quarter, up by a quarter
	var uv := panel.local_to_uv(hit)
	assert_eq(uv, Vector2(0.75, 0.25), "uv in each axis's own extent")
	assert_eq(XRWebPanel.uv_to_surface_px(uv, Vector2i(1920, 480)), Vector2(1440, 120), "pixel")


func test_a_scaled_panel_still_maps_its_own_corners() -> void:
	# The probe goes global hit -> to_local() -> local_to_uv(). If the node is
	# scaled, to_local() is what undoes it, so a corner of the scaled quad must
	# still be a corner of the page. Done with the node's own transform rather
	# than in the tree: a composition layer entering the tree headless reaches
	# for an XR global transform that is not there. For a node with no parent,
	# its transform is its global transform, so this is what to_local() does.
	panel.transform = Transform3D(Basis.from_scale(Vector3(2.0, 3.0, 1.0)), Vector3(1, 1.5, -2))
	var world := panel.transform
	var top_left := world * Vector3(-QUAD.x / 2.0, QUAD.y / 2.0, 0.0)
	assert_almost_eq(top_left.x, 1.0 - QUAD.x, 0.0001, "twice as wide in the world")
	assert_almost_eq(top_left.y, 1.5 + QUAD.y * 1.5, 0.0001, "three times as tall")
	var uv := panel.local_to_uv(world.affine_inverse() * top_left)
	assert_almost_eq(uv, Vector2(0.0, 0.0), Vector2(0.0001, 0.0001), "still the page's corner")

	var off_right := world * Vector3(QUAD.x / 2.0 + 0.01, 0.0, 0.0)
	var off_uv := panel.local_to_uv(world.affine_inverse() * off_right)
	assert_false(XRWebPanel.uv_is_on_panel(off_uv), "just past the scaled edge is off")


func test_the_cursor_script_carries_the_uv_and_hides_off_the_panel() -> void:
	assert_eq(
		XRWebPanel.cursor_script(Vector2(0.25, 0.75)),
		"window.xrCursor&&xrCursor(0.2500,0.7500)",
		"page fractions, fixed point"
	)
	assert_eq(
		XRWebPanel.cursor_script(Vector2(1.0, 0.0)),
		"window.xrCursor&&xrCursor(1.0000,0.0000)",
		"the edge is still on the panel"
	)
	var hidden := "window.xrCursor&&xrCursor(-1,-1)"
	assert_eq(XRWebPanel.cursor_script(Vector2(1.01, 0.5)), hidden, "past the right edge")
	assert_eq(XRWebPanel.cursor_script(Vector2(0.5, -0.01)), hidden, "above the top")
	assert_eq(XRWebPanel.cursor_script(XRWebPanel.CURSOR_HIDDEN), hidden, "the hidden marker")


func test_the_cursor_script_never_uses_exponent_notation() -> void:
	# str() of a tiny float is "1e-05", which is valid JavaScript but not what
	# a reader expects; more to the point, a format that ever emitted "nan" or
	# "inf" would throw in the page instead of moving the dot.
	assert_eq(
		XRWebPanel.cursor_script(Vector2(0.00001, 0.99999)),
		"window.xrCursor&&xrCursor(0.0000,1.0000)",
		"rounded, not 1e-05"
	)


func test_the_embed_page_has_a_cursor_that_cannot_take_input() -> void:
	var html := XRWebPanel.EMBED_TEMPLATE % "https://www.youtube.com/embed/x"
	assert_string_contains(html, 'id="xr-cursor"')
	assert_string_contains(html, "pointer-events:none")
	assert_string_contains(html, "function xrCursor(u, v)")
	# loadDataWithBaseURL is safe from URL decoding, but loadData() is not,
	# and the template must survive either: no fragment, no stray escape.
	var body := XRWebPanel.EMBED_TEMPLATE.replace("%s", "")
	assert_false(body.contains("%"), "no percent sign outside the format specifier")
	assert_eq(body.count("#"), 0, "no hash")


func test_cursor_updates_are_throttled_and_deduplicated() -> void:
	panel.cursor_interval_msec = 33
	panel._cursor_wanted = Vector2(0.5, 0.5)
	assert_true(panel.cursor_update_due(1000), "first move goes out")
	panel._cursor_sent = panel._cursor_wanted
	panel._cursor_sent_msec = 1000

	panel._cursor_wanted = Vector2(0.6, 0.5)
	assert_false(panel.cursor_update_due(1010), "10ms later is too soon")
	assert_true(panel.cursor_update_due(1033), "a whole interval later it goes")
	panel._cursor_sent = panel._cursor_wanted
	panel._cursor_sent_msec = 1033

	assert_false(panel.cursor_update_due(2000), "nothing to send when it has not moved")


func test_pointing_off_device_sends_nothing_and_does_not_throw() -> void:
	# No WebView, so point_at() must stop before reaching for the bridge.
	var stamp := panel._cursor_sent_msec
	assert_false(panel.point_at(Vector2(0.5, 0.5)), "nothing to move")
	assert_eq(panel._cursor_wanted, Vector2(0.5, 0.5), "but the wish is kept")
	assert_eq(panel._cursor_sent_msec, stamp, "a missed send does not spend the interval")
	assert_false(panel.point_at(Vector2(2.0, 0.5)), "off the panel")
	assert_eq(panel._cursor_wanted, XRWebPanel.CURSOR_HIDDEN, "is a request to hide")


func test_turning_the_cursor_off_is_a_request_to_hide_it() -> void:
	# A toggle that only stopped sending would leave the last dot on the page.
	panel.show_cursor = false
	assert_false(panel.point_at(Vector2(0.5, 0.5)), "nothing to move off-device")
	assert_eq(panel._cursor_wanted, XRWebPanel.CURSOR_HIDDEN, "the page is asked to hide")
	assert_string_contains(panel.cursor_status(), "show=false")
	assert_string_contains(panel.cursor_status(), "at=hidden")


func test_the_cursor_centre_is_the_point_the_touch_hits() -> void:
	# density_dpi 320 is a device pixel ratio of 2: a 1280x720 surface is a
	# 640x360 CSS viewport. The dot's centre and the touch are the same uv.
	var surface := Vector2i(1280, 720)
	var css := Vector2(surface) / 2.0
	var uv := Vector2(0.25, 0.75)
	var centre := XRWebPanel.cursor_css_center(uv, css)
	assert_eq(centre, Vector2(160, 270), "CSS pixel of the centre")
	assert_almost_eq(
		centre * 2.0, XRWebPanel.uv_to_surface_px(uv, surface), Vector2(0.001, 0.001), "same point"
	)
	assert_eq(XRWebPanel.CURSOR_DIAMETER_PX, 14.0, "the template's box")
	assert_eq(
		XRWebPanel.cursor_css_center(Vector2(1.01, 0.5), css),
		XRWebPanel.CURSOR_HIDDEN,
		"off the panel has no centre"
	)


func test_cursor_status_reports_the_wish() -> void:
	panel.point_at(Vector2(0.25, 0.5))
	assert_eq(panel.cursor_status(), "show=true embed=false at=0.25,0.50")
