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
