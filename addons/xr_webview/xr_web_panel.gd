class_name XRWebPanel
extends OpenXRCompositionLayerQuad

## A web page drawn by the XR compositor instead of by the game, built the way
## a headset's system browser is built rather than the way in-game browsers
## usually are.
##
## The conventional approach is to render an Android WebView to a texture and
## map it onto a quad. That copies the whole page every frame, samples it
## through the eye buffer - which is why in-game browsers look mushy next to
## the system one - and cannot show anything DRM-protected, because protected
## surfaces never capture.
##
## This goes the other way. use_android_surface asks the runtime, through
## XR_KHR_android_surface_swapchain, for an android.view.Surface backed by the
## compositor's own swapchain. A VirtualDisplay hosts a real WebView and draws
## into that surface, and the compositor samples the result at panel
## resolution, once, outside the render loop. Sharp text, hardware video
## decode, and nothing on the frame budget - measured at 90/90 FPS with no
## stale frames on a Quest Pro.
##
## What it costs: the layer is a flat quad the compositor owns, not geometry.
## No shaders on it, and depth only via hole punch, which is reported to
## misbehave on some Quest runtimes. If the panel ghosts or punches through
## things it should not, turn enable_hole_punch off and let it draw as an
## overlay instead.
##
## [b]Setup[/b]
##
## 1. Build the companion Android plugin: [code]just shim[/code], or the
##    equivalent for your project - it installs an AAR and a .gdap into
##    res://android/plugins, the only directory the Android exporter scans.
## 2. Enable it in the export preset. Godot detects the plugin but writes no
##    preset entry and defaults it to off, so the export succeeds with the
##    class absent and the panel silently loses JavaScript. The preset needs
##    [code]plugins/XRWebView=true[/code].
## 3. Add this node under XROrigin3D. Composition layers are posed against the
##    XR reference space, so keeping them under the origin is what makes their
##    transform read as world coordinates.
## 4. In the scene, set android_surface_size [i]before[/i] use_android_surface.
##    Setting the size once the flag is already true takes a different path
##    that calls xrUpdateSwapchainFB on a swapchain which does not exist yet,
##    and fails at session start with XR_ERROR_HANDLE_INVALID.
## 5. Set allowed_hosts and home_url. An empty allowlist loads nothing, on
##    purpose.
##
## Without the plugin the panel still runs - it just cannot turn JavaScript on,
## which is what probe_only is for.

## Emitted once the WebView is live on the compositor's surface.
signal surface_ready
## Emitted instead of navigating when a URL fails the allowlist.
signal navigation_blocked(url: String)

## android.hardware.display.DisplayManager flags. Spelled out rather than read
## off the class, because JavaClassWrapper static field access is one more
## thing to go wrong for two integers that have not moved since API 19.
## PRESENTATION lets a Presentation target the display; OWN_CONTENT_ONLY keeps
## it private to this app, which is what avoids needing a capture permission.
const VIRTUAL_DISPLAY_FLAG_PRESENTATION := 1 << 1
const VIRTUAL_DISPLAY_FLAG_OWN_CONTENT_ONLY := 1 << 3

## Context.DISPLAY_SERVICE.
const DISPLAY_SERVICE := "display"

## android.view.MotionEvent actions. Spelled out for the same reason the
## VirtualDisplay flags are: four integers that have not moved since API 1,
## against one more static field lookup that can fail at runtime.
const ACTION_DOWN := 0
const ACTION_UP := 1
const ACTION_MOVE := 2
const ACTION_CANCEL := 3

## Reported density of the virtual display. Only affects how the page sizes
## CSS pixels; 320 gives roughly desktop-like layout at 1280x720.
@export var density_dpi := 320

## The Java shim that reaches what GDScript cannot. See tools/jukebox-shim.
##
## WebSettings, WebViewClient and WebChromeClient are all unreachable from here
## - the first because its concrete class lives in the WebView provider's
## classloader, the other two because they are classes rather than
## single-method interfaces, so create_sam_callback cannot stand in. The shim
## takes the WebView as an argument and returns nothing, so the objects that
## cannot be wrapped never cross back.
##
## Built by `just shim` into android/plugins/. Absent from the build, the panel
## still runs - it just cannot turn JavaScript on, which is what probe_only is
## for.
const BRIDGE_CLASS := "com.cascadiacollections.xrwebview.XRWebViewBridge"

## Sent instead of the WebView default, which is a mobile user agent.
##
## Not cosmetic: under the mobile agent youtube.com redirects to m.youtube.com
## and from there reaches for an intent:// deep link to hand off to the
## installed app, which a Presentation has no Activity to launch. That is what
## left the panel blank the first time a real page was loaded.
## The origin the embed document claims to come from.
##
## YouTube's embed player refuses a top-level request - "Error 153", no Referer
## and no embedding origin - so the panel serves its own page and puts the
## player in an iframe, which is the embedding route YouTube's terms describe.
## This is the origin that page reports and the Referer the player sees, so it
## has to be a real https URL rather than about:blank or a data document.
@export var embed_base_url := "https://godot.example/xr-web-panel/"

## The page the panel serves to host an embed.
##
## Sized in viewport units, not pixels. density_dpi is 320, so the virtual
## display reports a device pixel ratio of 2 and a 1280x720 surface is a
## 640x360 CSS viewport - an iframe asked for 1280x720 comes out at twice the
## panel and the player is cropped to its top-left quarter. vw/vh track
## whatever the viewport turns out to be, and cost nothing if density_dpi
## changes later.
##
## No "#" or "%" outside the format specifier, for the reason PROBE_HTML
## carries at length - which is also why the sizes are vw/vh rather than the
## percentages this would otherwise be written with.
const EMBED_TEMPLATE := """
<html><head><meta name="viewport" content="width=device-width,initial-scale=1">
</head><body style="margin:0;background:rgb(0,0,0);overflow:hidden">
<iframe style="border:0;position:absolute;top:0;left:0;width:100vw;height:100vh"
allow="autoplay; encrypted-media" allowfullscreen src="%s"></iframe>
</body></html>
"""

const DESKTOP_USER_AGENT := (
	"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) "
	+ "Chrome/125.0.0.0 Safari/537.36"
)

## The probe page. No JavaScript, no network, no WebView settings - so if this
## does not appear, the surface itself is the problem and nothing else is.
## The corner markers double as a flip test; see _show_probe().
##
## Written without "#" or "%", which is not a style choice. loadData() puts the
## payload through URL decoding: "#" starts a fragment and truncates the
## document there, and "%" is read as an escape. An earlier version of this
## page used hex colours and "translate(-50%,-50%)" to centre, and drew white
## on the Quest Pro - the body was cut at the first colour. rgb() and flex
## centring avoid both characters. loadDataWithBaseURL() would also work, but
## takes a null base URL that is awkward to pass through JavaClassWrapper.
const PROBE_HTML := """
<html><body style="margin:0;height:100vh;display:flex;align-items:center;
justify-content:center;background:rgb(16,16,24);color:rgb(238,238,238);
font:40px sans-serif">
<div style="position:absolute;top:0;left:0;background:rgb(51,170,255);
color:rgb(0,0,0);padding:6px 14px">TOP LEFT</div>
<div style="position:absolute;bottom:0;right:0;background:rgb(255,170,51);
color:rgb(0,0,0);padding:6px 14px">BOTTOM RIGHT</div>
<div>jukebox surface OK</div>
</body></html>
"""

## Where the panel starts.
##
## A video rather than a home page, because nothing here injects input yet:
## a controller ray has no way to press anything, so a page you have to click
## proves only that the surface is alive. This one starts on its own -
## setMediaPlaybackRequiresUserGesture is off below - and exercises the whole
## path in one go: surface, orientation, and hardware decode. It is Blender's
## Big Buck Bunny at 4K60 (CC-BY), which is the same film GodotVR's
## android-surface example ships, and it needs no account.
@export var home_url := ""

## Hosts this panel may visit, matched on the registrable host and any
## subdomain of it. A browser in a social VR app is a screen a player can put
## anything on in front of strangers, which is both a Meta store problem and a
## moderation one, so navigation is allow-listed rather than open.
##
## Deliberately fail-closed: an empty list loads nothing at all. A panel that
## silently turns into an open browser when someone clears a field is the bug
## this ordering exists to prevent.
@export var allowed_hosts: PackedStringArray = []

## Let the page start audio without a tap. A jukebox that needs a click it has
## no cursor for is not a jukebox.
@export var allow_autoplay := true

## Draw the probe page instead of navigating to home_url.
##
## On by default because on Android P and up the panel cannot do its real job
## yet: _apply_settings() is unreachable, so JavaScript stays off, and
## home_url cannot render whatever it points at. Loading it anyway would put
## a broken page on the wall and tell us nothing. The probe tells us the one
## thing still unknown - whether the compositor surface is alive.
##
## Turn this off once a settings shim exists.
@export var probe_only := true

## Serve home_url inside an iframe on our own page rather than navigating to it.
##
## On for the embed players this panel exists to show. Off navigates directly,
## which is right for an ordinary page and wrong for anything that checks who
## is embedding it.
@export var use_iframe_embed := true

## Java proxies handed to the UI thread that have not run yet. Nothing else on
## our side holds them, and a collected callback is a panel that never appears
## with nothing in the log. Static because a runnable can outlive this node,
## and locked because the callback clears its own entry from the UI thread.
static var _in_flight: Dictionary = {}
static var _in_flight_lock := Mutex.new()
static var _next_token := 0

# Untyped on purpose: these are Java objects whose methods exist only at
# runtime, and a typed JavaObject would fail GDScript's static check on
# the first getSystemService() or loadUrl().
var _web_view
var _presentation
var _virtual_display
var _pending_url := ""
var _touch_down_msec := 0


func _ready() -> void:
	if OS.get_name() != "Android":
		# Nothing can fill this surface off-device, and asking the runtime for
		# a swapchain we will never write to is worse than not asking. Running
		# flat on the desktop is the normal case while iterating on gameplay.
		use_android_surface = false
		visible = false
		return

	var interface := XRServer.find_interface("OpenXR") as OpenXRInterface
	if interface == null:
		push_warning("XRWebPanel: no OpenXR interface; the panel stays dark.")
		return

	# The surface does not exist until the session does. Connected here rather
	# than in game.gd because child _ready() runs first: XRBoot.start() has not
	# been called yet, so the signal cannot have been missed.
	interface.session_begun.connect(_on_session_begun, CONNECT_ONE_SHOT)


## Whether this runtime and renderer pair hands back an upside-down surface.
##
## XR_KHR_android_surface_swapchain is implemented inconsistently: the Oculus
## runtime flips under the GL drivers, Pico flips under Vulkan, and the two
## cancel out if you assume either one is the rule. Taken from GodotVR's own
## android-surface example, which is where this was found out the hard way.
static func needs_vertical_flip(runtime_name: String, driver_name: String) -> bool:
	if runtime_name.begins_with("Oculus"):
		return driver_name.begins_with("opengl3")
	if runtime_name.begins_with("Pico"):
		return driver_name == "vulkan"
	return false


## The host part of a URL, lowercased, with any scheme, credentials, port and
## path removed. Returns "" for anything it cannot make sense of.
static func host_of(url: String) -> String:
	var rest := url.strip_edges().to_lower()
	var scheme := rest.find("://")
	if scheme != -1:
		rest = rest.substr(scheme + 3)

	# The authority ends at the first of these; everything after is not host.
	for sep in ["/", "?", "#"]:
		var at := rest.find(sep)
		if at != -1:
			rest = rest.substr(0, at)

	# user:pass@host - the host is whatever follows the last '@'. Taking the
	# first would let "youtube.com@evil.example" read as YouTube.
	var credentials := rest.rfind("@")
	if credentials != -1:
		rest = rest.substr(credentials + 1)

	if rest.begins_with("["):  # [::1]:8080 - the colons inside are not a port.
		var close := rest.find("]")
		return rest.substr(0, close + 1) if close != -1 else ""

	var port := rest.rfind(":")
	if port != -1:
		rest = rest.substr(0, port)
	return rest


## Whether the panel is allowed to navigate here.
##
## https only, on purpose. A WebView will happily follow file://, content://
## and javascript: URLs, and the first two are a route out of the app sandbox
## and into our own save data.
static func is_allowed(url: String, hosts: PackedStringArray) -> bool:
	if not url.strip_edges().to_lower().begins_with("https://"):
		return false

	var host := host_of(url)
	if host.is_empty():
		return false

	for entry in hosts:
		var allowed := entry.strip_edges().to_lower()
		# Suffix match on a dot boundary: "youtube.com" covers
		# "music.youtube.com" but must not cover "notyoutube.com".
		if not allowed.is_empty() and (host == allowed or host.ends_with("." + allowed)):
			return true
	return false


## Point the panel somewhere. Returns false if the allowlist refused it.
## Safe to call before the surface exists; the URL is held until it does.
func load_url(url: String) -> bool:
	if not is_allowed(url, allowed_hosts):
		# Deferred: load_url can be reached from the Android UI thread.
		navigation_blocked.emit.call_deferred(url)
		push_warning("XRWebPanel: refused to navigate to '%s' - not in allowed_hosts." % url)
		return false

	_pending_url = url
	if _web_view != null:
		_run_on_ui_thread(_load_pending)
	return true


## Whether there is a live WebView on the compositor's surface.
func is_live() -> bool:
	return _web_view != null


## Where a point on the panel's surface falls, as 0..1 across the quad.
##
## Takes a position in this node's local space - what a raycast gives after
## to_local(). The quad is centred on its origin in the XY plane, and page
## coordinates run down from the top left, so y is flipped on the way.
##
## Returns values outside 0..1 for a point off the panel; send_touch() refuses
## those rather than clamping, because a ray that has slid off the edge should
## stop the drag, not pin it to the border.
func local_to_uv(local_position: Vector3) -> Vector2:
	return Vector2(0.5 + local_position.x / quad_size.x, 0.5 - local_position.y / quad_size.y)


## Whether a uv from local_to_uv() actually lands on the panel.
static func uv_is_on_panel(uv: Vector2) -> bool:
	return uv.x >= 0.0 and uv.x <= 1.0 and uv.y >= 0.0 and uv.y <= 1.0


## Deliver a touch to the page. Returns false if it went nowhere.
##
## The panel lives on a VirtualDisplay no finger will ever touch, so every
## event the page sees has to be manufactured: MotionEvent.obtain() builds one
## and View.dispatchTouchEvent() hands it to the WebView directly. None of this
## needs the Java plugin - MotionEvent is a framework class the app classloader
## can see and obtain() is static, so unlike WebSettings it wraps cleanly.
##
## Nor does it need the INJECT_EVENTS permission, which guards system-wide
## injection into other apps' windows; this is our own view hierarchy.
##
## A tap is ACTION_DOWN then ACTION_UP at the same point. A drag is DOWN, any
## number of MOVEs, then UP. ACTION_CANCEL is what to send when the ray leaves
## the panel mid-drag, so the page does not sit waiting for an UP that has
## already gone somewhere else.
func send_touch(action: int, uv: Vector2) -> bool:
	if not uv_is_on_panel(uv):
		return false
	if _web_view == null:
		return false

	var point := Vector2(uv.x * android_surface_size.x, uv.y * android_surface_size.y)
	var now := _uptime_msec()
	if action == ACTION_DOWN:
		# Every event in a gesture carries the time its DOWN happened. Android
		# reads the difference as the gesture's duration, which is how a page
		# tells a tap from a long press and how it derives fling velocity.
		_touch_down_msec = now

	_run_on_ui_thread(_dispatch_touch.bind(action, point, _touch_down_msec, now))
	return true


## A press and release at one point, which is what a page reads as a click.
func tap(uv: Vector2) -> bool:
	return send_touch(ACTION_DOWN, uv) and send_touch(ACTION_UP, uv)


## android.os.SystemClock.uptimeMillis(), which is the clock MotionEvent wants.
##
## Godot's own tick count starts when the engine does, so gestures built on it
## would carry timestamps from a different epoch to every other event the page
## receives. Falls back to it anyway off-device, where nothing dispatches.
func _uptime_msec() -> int:
	var clock = JavaClassWrapper.wrap("android.os.SystemClock")
	if clock == null:
		return Time.get_ticks_msec()
	return clock.uptimeMillis()


## Runs on the Android UI thread: dispatchTouchEvent has the same thread rule
## as every other View call here.
func _dispatch_touch(action: int, point: Vector2, down_msec: int, event_msec: int) -> void:
	if _web_view == null:
		return

	var motion_event = JavaClassWrapper.wrap("android.view.MotionEvent")
	if motion_event == null:
		push_warning("XRWebPanel: android.view.MotionEvent is unavailable.")
		return

	var event = motion_event.obtain(down_msec, event_msec, action, point.x, point.y, 0)
	if event == null:
		_report_java_exception("building a touch event")
		return

	_web_view.dispatchTouchEvent(event)
	# Returned to Android's pool rather than left to the collector: a gesture
	# is three to dozens of these, and MotionEvent is the allocation Android
	# most expects to get back.
	event.recycle()
	_report_java_exception("dispatching a touch event")


func _on_session_begun() -> void:
	var interface := XRServer.find_interface("OpenXR") as OpenXRInterface
	var runtime: String = interface.get_system_info().get("XRRuntimeName", "")
	var driver := RenderingServer.get_current_rendering_driver_name()
	var flip := XRWebPanel.needs_vertical_flip(runtime, driver)
	set("XR_FB_composition_layer_image_layout/vertical_flip", flip)
	print("XRWebPanel: runtime=%s driver=%s vertical_flip=%s" % [runtime, driver, flip])

	var surface = get_android_surface()
	if surface == null:
		# Either the runtime lacks XR_KHR_android_surface_swapchain or the
		# layer was not configured for one before the session came up.
		push_warning("XRWebPanel: OpenXR returned no Android surface.")
		return

	_run_on_ui_thread(_attach_web_view.bind(surface))


## Builds the VirtualDisplay, the Presentation and the WebView, and points the
## last of them at the compositor's surface. Runs on the Android UI thread -
## every Android View API below requires it.
func _attach_web_view(surface) -> void:
	var activity = _get_activity()
	if activity == null:
		return

	var display_manager = activity.getSystemService(DISPLAY_SERVICE)
	_virtual_display = display_manager.createVirtualDisplay(
		"jukebox",
		android_surface_size.x,
		android_surface_size.y,
		density_dpi,
		surface,
		VIRTUAL_DISPLAY_FLAG_PRESENTATION | VIRTUAL_DISPLAY_FLAG_OWN_CONTENT_ONLY
	)
	if _virtual_display == null:
		_report_java_exception("creating the virtual display")
		return

	# A Presentation is how an app puts its own views on a secondary display.
	# It is what lets this be a real, hardware-accelerated WebView - with
	# working video decode - rather than a view drawn by hand into a canvas,
	# which is where the texture-copy approach loses DRM playback.
	var presentation_class = JavaClassWrapper.wrap("android.app.Presentation")
	_presentation = presentation_class.Presentation(activity, _virtual_display.getDisplay())

	var web_view_class = JavaClassWrapper.wrap("android.webkit.WebView")
	_web_view = web_view_class.WebView(_presentation.getContext())

	# Content on screen before anything that can fail. _apply_settings() aborts
	# on Android P and up (see its comment); when it ran first, the abort took
	# setContentView() and show() with it and the panel stayed grey with only a
	# ClassNotFoundException to explain it.
	_presentation.setContentView(_web_view)
	_presentation.show()
	_report_java_exception("attaching the web view")

	# emit() is rejected off the Godot thread, and this is the Android UI one.
	surface_ready.emit.call_deferred()

	if probe_only:
		_show_probe()
		return
	_apply_settings()
	if _pending_url.is_empty():
		load_url(home_url)
	else:
		_load_pending()


## Draws a page that needs no JavaScript, no network and no settings, so that
## what reaches the compositor depends on nothing but the surface itself.
##
## This is the experiment that separates the two things a grey panel could
## mean: a dead swapchain, or a live one with nothing drawn into it. The
## corner markers answer the vertical-flip question at the same time - TOP
## LEFT appearing bottom-right is a flip, and needs_vertical_flip() is wrong
## for this runtime and renderer.
func _show_probe() -> void:
	_web_view.loadData(PROBE_HTML, "text/html", "utf-8")
	_report_java_exception("loading the probe page")


## The three WebView settings this panel needs, none of which can currently be
## applied from GDScript.
##
## Since Android P the WebView implementation lives in its own classloader.
## WebSettings is abstract and the instance behind it is
## com.android.webview.chromium.ContentSettingsAdapter, which the app
## classloader cannot see. JavaClassWrapper wraps a return value by its
## concrete class, so the wrap fails, getSettings() never becomes callable,
## and the call below raises "Invalid call. Nonexistent function 'getSettings'"
## and aborts this function. Reflection does not help: Method.invoke() has to
## hand the same unwrappable object back across the same boundary.
##
## Left in place because it is correct, it works before Android P, and it is
## what a Kotlin shim would replace - see the README. Called last, and only
## when probe_only is off, so that its failure costs nothing already drawn.
func _apply_settings() -> void:
	var bridge = JavaClassWrapper.wrap(BRIDGE_CLASS)
	if bridge == null:
		push_warning(
			"XRWebPanel: %s missing; JavaScript stays off. Run `just shim`." % BRIDGE_CLASS
		)
		return

	bridge.configure(_web_view, allow_autoplay, DESKTOP_USER_AGENT)
	# Enforced in Java as well as at load_url(), because a link the page itself
	# follows never passes through GDScript to be checked.
	bridge.installClients(_web_view, ",".join(allowed_hosts))
	_report_java_exception("applying settings")


func _load_pending() -> void:
	if _web_view == null or _pending_url.is_empty():
		return

	if use_iframe_embed:
		var bridge = JavaClassWrapper.wrap(BRIDGE_CLASS)
		if bridge != null:
			var html := EMBED_TEMPLATE % _pending_url
			bridge.loadEmbed(_web_view, embed_base_url, html)
			_report_java_exception("loading the embed document")
			return

	_web_view.loadUrl(_pending_url)


func _get_activity():
	var runtime = Engine.get_singleton("AndroidRuntime")
	if runtime == null:
		push_warning("XRWebPanel: no AndroidRuntime singleton.")
		return null
	return runtime.getActivity()


## Post work to the Android UI thread. Godot's own thread is not it, and every
## View call in this file would throw from anywhere else.
func _run_on_ui_thread(work: Callable) -> void:
	var activity = _get_activity()
	if activity == null:
		return

	var token := _next_token
	_next_token += 1

	var once := func() -> void:
		if work.is_valid():
			work.call()
		_in_flight_lock.lock()
		_in_flight.erase(token)
		_in_flight_lock.unlock()

	var runnable = JavaClassWrapper.create_sam_callback("java.lang.Runnable", once)
	_in_flight_lock.lock()
	_in_flight[token] = runnable
	_in_flight_lock.unlock()
	activity.runOnUiThread(runnable)


func _report_java_exception(doing: String) -> void:
	var exception = JavaClassWrapper.get_exception()
	if exception != null:
		push_error("XRWebPanel: Java exception while %s: %s" % [doing, exception])


func _exit_tree() -> void:
	if _presentation == null and _virtual_display == null:
		return

	# Captured as locals: the teardown runs after this node is on its way out,
	# and the closure must not reach back through it.
	var web_view = _web_view
	var presentation = _presentation
	var virtual_display = _virtual_display
	_web_view = null
	_presentation = null
	_virtual_display = null

	_run_on_ui_thread(
		func() -> void:
			if web_view != null:
				# Stop playback before tearing the surface out from under it.
				web_view.loadUrl("about:blank")
				web_view.destroy()
			if presentation != null:
				presentation.dismiss()
			if virtual_display != null:
				virtual_display.release()
	)
