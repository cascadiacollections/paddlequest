class_name XRBoot
extends RefCounted

## Ceiling on the display refresh rate. 0 means "whatever the headset offers".
## A Quest Pro tops out at 90Hz; a Quest 3 will offer 120Hz, which is worth
## capping if a scene ever gets heavy enough to miss frames.
const MAX_REFRESH_RATE := 0.0

## Fixed foveated rendering: shade the periphery at lower resolution. On a
## tiled mobile GPU this is close to free performance, and at level 2 with
## dynamic adjustment it is not noticeable in normal play.
const FOVEATION_LEVEL := 0
const FOVEATION_DYNAMIC := true

## Supersampling of the eye render targets. 1.0 is the runtime's recommendation;
## this scene has enough headroom on an Adreno 650 to push past it for a
## sharper image.
const RENDER_SCALE := 1.0


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
		openxr.session_begun.connect(
			XRBoot._tune_session.bind(openxr), CONNECT_ONE_SHOT
		)

	return true


static func _tune_session(openxr: OpenXRInterface) -> void:
	_use_fastest_refresh_rate(openxr)

	openxr.foveation_level = FOVEATION_LEVEL
	openxr.foveation_dynamic = FOVEATION_DYNAMIC
	# Subsampled images and the render scale both feed swapchain creation, so
	# they are only applied if asked for; setting them from session_begun is
	# already too late for the swapchain and blanked the view.
	if RENDER_SCALE != 1.0:
		openxr.render_target_size_multiplier = RENDER_SCALE
	print("OpenXR: foveation=%d dynamic=%s render_scale=%.2f" % [
		openxr.foveation_level, openxr.foveation_dynamic,
		openxr.render_target_size_multiplier,
	])


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
