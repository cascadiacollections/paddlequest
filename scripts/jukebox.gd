class_name Jukebox
extends XRWebPanel

## The court's web panel: an XRWebPanel carrying this game's configuration.
##
## Everything that makes a compositor-backed WebView work lives in
## addons/xr_webview, so it can be revised - and eventually shipped to other
## Godot XR projects - without touching the game. What stays here is only what
## is true of this court.
##
## Where the node sits, since a .tscn cannot keep a comment past the first
## time someone opens the scene in the editor and saves it: the panel is flat
## against the inside face of the left wall at x = -2.99, turned to face +X
## into the court. It hangs off XROrigin3D, which is identity in main.tscn, so
## those read as world coordinates.


## Configuration lives here rather than in the scene so that changing it shows
## up in a diff instead of being buried in a .tscn. A scene that sets one of
## these still wins: scene properties are applied after _init().
func _init() -> void:
	# A video rather than a home page, because nothing here injects input yet:
	# a controller ray has no way to press anything, so a page you have to
	# click proves only that the surface is alive. This one starts on its own
	# and exercises the whole path in one go - surface, orientation, and
	# hardware decode. It is Blender's Big Buck Bunny at 4K60 (CC-BY), which
	# needs no account.
	#
	# The embed player, not the watch page: a top-level request to /embed/
	# comes back as "Error 153" because there is no Referer and no embedding
	# origin, and the watch page reaches for an intent:// deep link that a
	# Presentation has no Activity to launch. use_iframe_embed is what puts
	# the player in a document with an origin of its own.
	home_url = "https://www.youtube.com/embed/aqz-KE-bpKQ?autoplay=1&playsinline=1&rel=0"
	embed_base_url = "https://cascadiacollections.github.io/paddlequest/"

	# A browser in a VR app is a screen a player can put anything on in front
	# of other people, which is a store-review problem before it is a
	# moderation one. Deliberately fail-closed, and enforced in Java too, so a
	# link the page itself follows is checked as well.
	allowed_hosts = [
		"youtube.com",
		"spotify.com",
		"soundcloud.com",
		"bandcamp.com",
	]

	# The panel can do its real job now that the Android plugin ships with the
	# build. Turn this back on to isolate the surface from the page when
	# something looks wrong in the headset.
	probe_only = false
