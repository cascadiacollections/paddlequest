extends Node3D

## Debug harness for the jukebox composition layer. Not part of the game.
##
## The jukebox panel came up blank on a Quest Pro and the main scene is a bad
## place to find out why: the panel hangs on the left wall, so "did it render"
## and "am I looking at it" are the same question, the wall can occlude it, the
## origin carries the locomotion script, and every answer costs a full rebuild.
##
## This scene strips all of that out. Two composition layer quads sit side by
## side in front of the camera, identical but for one thing:
##
##   left  - CONTROL, fed by a SubViewport with a magenta rectangle in it.
##   right - SURFACE, fed by an Android surface, running scripts/jukebox.gd.
##
## Control renders but surface does not  -> the fault is the Android surface
## path: the WebView's pixels are not reaching the compositor.
## Neither renders                       -> the fault is the layer itself, and
## the WebView was never the problem.
## Both render                           -> the layer and the surface are fine
## and whatever is wrong is in the page.
##
## The Label3D between them carries the state that print() does not reliably
## get into logcat - runtime, driver, whether the surface came back null, and
## whether the WebView went live.
##
## Run with: just probe

const REFRESH_INTERVAL := 0.5

## How long to let the page settle before the input test fires.
##
## Nothing here holds a controller, so the panel is tapped on a timer instead.
## The embed player toggles play/pause on a click in the middle, which is an
## effect that can be read from across the room - if the video stops, the
## MotionEvent reached the page.
const TAP_AFTER := 12.0

@onready var control_quad: OpenXRCompositionLayerQuad = $XROrigin3D/ControlQuad
@onready var surface_quad: OpenXRCompositionLayerQuad = $XROrigin3D/SurfaceQuad
@onready var status: Label3D = $XROrigin3D/Status
@onready var right_hand: XRController3D = $XROrigin3D/RightHand

var _elapsed := 0.0
var _viewport_was_null := false
var _since_ready := 0.0
var _tap_result := "waiting"
var _dragging := false
var _last_uv := Vector2(0.5, 0.5)
var _on_panel := false
var _last_action := "none"
var _blocked_url := ""
var _surface_ready := false


func _ready() -> void:
	# Assigned here rather than trusted to the scene file, and before
	# XRBoot.start() rather than after. layer_viewport is an object property
	# serialised as a NodePath, and this scene was hand-written rather than
	# saved by the editor. Order matters: set_layer_viewport() only allocates
	# the layer's swapchain when _should_register() passes, and that requires
	# the layer not to be registered yet - once the session has begun it is,
	# and a later assignment is silently ignored.
	if control_quad.layer_viewport == null:
		_viewport_was_null = true
		control_quad.layer_viewport = $XROrigin3D/ControlQuad/SubViewport

	XRBoot.start(get_viewport())

	# Both signals report into the label rather than the log, since this whole
	# scene exists to be read through the headset.
	if surface_quad.has_signal("surface_ready"):
		surface_quad.surface_ready.connect(func() -> void: _surface_ready = true)
		surface_quad.navigation_blocked.connect(func(url: String) -> void: _blocked_url = url)

	_refresh()


func _process(delta: float) -> void:
	if _surface_ready and _tap_result == "waiting":
		_since_ready += delta
		if _since_ready >= TAP_AFTER:
			var sent: bool = surface_quad.tap(Vector2(0.5, 0.5))
			_tap_result = "sent, video should pause" if sent else "REFUSED"

	_aim()

	_elapsed += delta
	if _elapsed < REFRESH_INTERVAL:
		return
	_elapsed = 0.0
	_refresh()


## Points the right hand at the panel and turns the trigger into touches.
##
## The ray is intersected with the quad's plane rather than raycast at a
## collision shape, because the quad has none - a composition layer is not
## geometry, and giving it an Area3D just to be pointed at would be a body
## that exists only to be hit.
func _aim() -> void:
	var origin := right_hand.global_position
	var direction := -right_hand.global_transform.basis.z
	var normal := surface_quad.global_transform.basis.z

	var denominator := direction.dot(normal)
	var uv := Vector2(-1.0, -1.0)
	if absf(denominator) > 0.0001:
		var distance := (surface_quad.global_position - origin).dot(normal) / denominator
		if distance > 0.0:
			var hit := origin + direction * distance
			uv = surface_quad.local_to_uv(surface_quad.to_local(hit))

	# The cursor is drawn by the page, not here. A bead at the hit point is
	# what this used to do, and it was never visible: the composition layer is
	# composited over the eye buffer, so it covered the bead however close to
	# the panel it sat.
	surface_quad.point_at(uv)
	_on_panel = XRWebPanel.uv_is_on_panel(uv)
	if _on_panel:
		_last_uv = uv

	var held := right_hand.is_button_pressed("trigger_click")
	if held and not _dragging and _on_panel:
		_dragging = true
		_act("DOWN", surface_quad.send_touch(XRWebPanel.ACTION_DOWN, uv))
	elif held and _dragging:
		if _on_panel:
			_act("MOVE", surface_quad.send_touch(XRWebPanel.ACTION_MOVE, uv))
		else:
			# Off the edge mid-drag: end it where it was last real, rather than
			# leaving the page waiting for an UP that has gone elsewhere.
			_dragging = false
			_act("CANCEL", surface_quad.send_touch(XRWebPanel.ACTION_CANCEL, _last_uv))
	elif not held and _dragging:
		_dragging = false
		_act("UP", surface_quad.send_touch(XRWebPanel.ACTION_UP, _last_uv))


func _act(name: String, sent: bool) -> void:
	_last_action = "%s %s" % [name, "sent" if sent else "REFUSED"]


func _refresh() -> void:
	status.text = "\n".join(_lines())


func _lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append(
		"os=%s driver=%s" % [OS.get_name(), RenderingServer.get_current_rendering_driver_name()]
	)

	var interface := XRServer.find_interface("OpenXR") as OpenXRInterface
	if interface == null:
		lines.append("openxr: NO INTERFACE")
	else:
		var runtime: String = interface.get_system_info().get("XRRuntimeName", "?")
		var version: String = interface.get_system_info().get("XRRuntimeVersion", "?")
		lines.append("runtime=%s %s" % [runtime, version])
		lines.append("initialized=%s" % interface.is_initialized())

	lines.append("")
	lines.append(
		(
			"CONTROL  native=%s visible=%s"
			% [control_quad.is_natively_supported(), control_quad.is_visible_in_tree()]
		)
	)
	lines.append(
		(
			"         viewport=%s scene_was_null=%s"
			% ["null" if control_quad.layer_viewport == null else "set", _viewport_was_null]
		)
	)

	var surface = surface_quad.get_android_surface()
	lines.append(
		(
			"SURFACE  native=%s visible=%s"
			% [surface_quad.is_natively_supported(), surface_quad.is_visible_in_tree()]
		)
	)
	lines.append("         android_surface=%s" % ("null" if surface == null else "ok"))
	lines.append("         webview_live=%s ready=%s" % [surface_quad.is_live(), _surface_ready])
	lines.append("         tap=%s" % _tap_result)
	lines.append("         protected=%s" % surface_quad.protected_content)
	lines.append("")
	lines.append("AIM      on_panel=%s uv=%.2f,%.2f" % [_on_panel, _last_uv.x, _last_uv.y])
	lines.append("         last=%s" % _last_action)
	# The dot itself is in the page. This is the wish point_at() is holding,
	# which is readable in the headset when the dot is the thing under test.
	lines.append("         cursor=%s" % surface_quad.cursor_status())
	if not _blocked_url.is_empty():
		lines.append("         BLOCKED %s" % _blocked_url)

	return lines
