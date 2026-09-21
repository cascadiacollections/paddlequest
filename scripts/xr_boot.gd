class_name XRBoot
extends RefCounted

## Ceiling on the display refresh rate. 0 means "whatever the headset offers".
## A Quest Pro tops out at 90Hz, a Quest 3 offers 120Hz, and a Steam Frame
## offers 72/80/90/120 plus an experimental 144Hz.
##
## Taking the fastest rate on offer is only safe because physics interpolation
## is on (see physics/common/physics_interpolation in project.godot): the
## render rate no longer has to relate to the 90Hz physics tick. Cap this if a
## scene ever gets heavy enough to miss frames at the top rate - dropping
## frames at 120 is worse than holding 90.
const MAX_REFRESH_RATE := 0.0

## Foveation is configured through xr/openxr/foveation_level and
## foveation_dynamic in project.godot, not from here. Both feed session and
## swapchain setup, so the engine has to apply them during initialisation;
## setting them afterwards from session_begun left the headset rendering
## nothing at all while audio carried on.


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

	var openxr := interface as OpenXRInterface
	if openxr != null:
		# The rate can only be raised once the session is actually running.
		# Setting it straight after initialize() is silently ignored, which is
		# why the headset otherwise sits at its 72Hz default.
		openxr.session_begun.connect(XRBoot._tune_session.bind(openxr), CONNECT_ONE_SHOT)

	return true


static func _tune_session(openxr: OpenXRInterface) -> void:
	_use_fastest_refresh_rate(openxr)
	# Reported, not assigned: these come from project.godot.
	var settings := [
		openxr.foveation_level,
		openxr.foveation_dynamic,
		openxr.render_target_size_multiplier,
	]
	print("OpenXR: foveation=%d dynamic=%s render_scale=%.2f" % settings)


static func _use_fastest_refresh_rate(openxr: OpenXRInterface) -> void:
	var best := 0.0
	for rate in openxr.get_available_display_refresh_rates():
		var hz := float(rate)
		if MAX_REFRESH_RATE > 0.0 and hz > MAX_REFRESH_RATE:
			continue
		best = maxf(best, hz)

	if best <= 0.0:
		push_warning("OpenXR: no display refresh rates reported.")
		return

	openxr.display_refresh_rate = best
	print("OpenXR: display refresh rate set to %.0f Hz" % best)
