extends Control

## Desktop stand-in for the in-page cursor. Not part of the game.
##
## A composition layer is composited over the eye buffer, so the dot that
## matters in the headset has to live in the page, and that page does not
## exist off-device. This draws the same centre, from the same uv, in an
## ordinary Control. The dot's mouse filter is IGNORE, which is the desktop
## version of the page's pointer-events: none.
##
## Run with: just cursor-preview
## Press C to toggle the dot. Pass `-- --uv=0.25,0.5` to pin it for a
## screenshot; while that pin is set the mouse is not followed.

## CSS viewport of a 1280x720 surface at density_dpi 320 (device pixel ratio 2).
const CSS_SIZE := Vector2(640, 360)

@export var show_cursor := true
@export var track_mouse := true

@onready var _page: ColorRect = $Page
@onready var _cursor: ColorRect = $Page/Cursor
@onready var _hint: Label = $Hint

var _uv := XRWebPanel.CURSOR_HIDDEN
var _pinned := false


func _ready() -> void:
	_page.custom_minimum_size = CSS_SIZE
	_page.size = CSS_SIZE
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor.size = Vector2(XRWebPanel.CURSOR_DIAMETER_PX, XRWebPanel.CURSOR_DIAMETER_PX)
	_apply_pin(OS.get_cmdline_user_args())
	_apply()
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(Vector2i(int(CSS_SIZE.x), int(CSS_SIZE.y) + 36))


func _process(_delta: float) -> void:
	if _pinned or not track_mouse:
		return
	var local := _page.get_local_mouse_position()
	var size := _page.size
	var inside := local.x >= 0.0 and local.y >= 0.0 and local.x <= size.x and local.y <= size.y
	if size.x <= 0.0 or size.y <= 0.0 or not inside:
		place(XRWebPanel.CURSOR_HIDDEN)
	else:
		place(Vector2(local.x / size.x, local.y / size.y))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C:
		show_cursor = not show_cursor
		_apply()


## Move the dot to uv, or hide it when uv is off the page.
func place(uv: Vector2) -> void:
	_uv = uv
	_apply()


func _apply() -> void:
	var centre := XRWebPanel.cursor_css_center(_uv, _page.size)
	var visible_dot := show_cursor and XRWebPanel.uv_is_on_panel(_uv)
	_cursor.visible = visible_dot
	if visible_dot:
		# position is the top-left. The page centres with a negative margin
		# of half the diameter; this is that same shift.
		_cursor.position = centre - _cursor.size / 2.0
	_hint.text = (
		"C toggles the dot (%s). %s"
		% [
			"on" if show_cursor else "off",
			"pinned" if _pinned else "move the mouse over the page",
		]
	)


func _apply_pin(args: PackedStringArray) -> void:
	for arg in args:
		if not arg.begins_with("--uv="):
			continue
		var parts := arg.trim_prefix("--uv=").split(",")
		if parts.size() != 2 or not parts[0].is_valid_float() or not parts[1].is_valid_float():
			push_warning("cursor preview: expected --uv=0.25,0.5")
			return
		_pinned = true
		track_mouse = false
		_uv = Vector2(float(parts[0]), float(parts[1]))
