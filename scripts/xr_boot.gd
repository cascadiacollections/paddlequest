class_name XRBoot
extends RefCounted

## Brings up the OpenXR interface.
##
## Returns true when a headset is driving the viewport. False means OpenXR was
## unavailable and we are rendering flat on the desktop, which is the normal
## case while iterating on gameplay from the editor.
static func start(viewport: Viewport) -> bool:
	var interface := XRServer.find_interface("OpenXR")
	if interface == null or not interface.is_initialized() and not interface.initialize():
		push_warning("OpenXR unavailable - running flat on the desktop.")
		return false

	viewport.use_xr = true
	# The headset compositor paces us; a second limiter only fights it.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	return true
