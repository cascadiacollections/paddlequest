extends Node3D

## In-headset menu: pause, recenter, the comfort toggles, and a way out.
##
## Before this there was no way out of the game from inside the headset at
## all - game.gd handled ui_cancel but gated it on `not _xr` - and no
## recenter anywhere in the project, which every seated VR app needs.
##
## Driven by the thumbstick and the trigger rather than by a pointer and a
## raycast. A laser pointer is the conventional answer and is a great deal
## more machinery: a SubViewport, a collision shape per control, ray
## intersection, hover states. A six-item list does not need any of that,
## and stick-and-trigger works identically on Touch and on Steam Frame
## without knowing anything about either.
##
## Deliberately does NOT use get_tree().paused. Pausing the tree stops
## XRCamera3D too, which locks the rendered world to the head - the single
## most reliable way to make someone ill in VR - and stops XRController3D
## emitting, which would leave the menu unable to be dismissed. Gameplay is
## suspended instead: game.gd freezes the ball and locks locomotion while
## this is open, and tracking carries on as normal.

signal opened
signal closed

const RESUME := "resume"
const RECENTER := "recenter"
const VIGNETTE := "comfort_vignette"
const SNAP_TURN := "snap_turn"
const SEATED := "seated"
const QUIT := "quit"

## In display order. Toggles read their state from SaveGame; the others act.
const ITEMS: Array[String] = [RESUME, RECENTER, VIGNETTE, SNAP_TURN, SEATED, QUIT]

const LABELS := {
	RESUME: "Resume",
	RECENTER: "Recenter",
	VIGNETTE: "Comfort vignette",
	SNAP_TURN: "Snap turn",
	SEATED: "Seated",
	QUIT: "Quit",
}

## How far in front of the head the panel appears when opened.
@export var distance := 1.1
## Stick deflection needed to move the selection, and how long to wait before
## a held stick repeats.
@export var stick_threshold := 0.6
@export var repeat_delay := 0.25
@export var controller_path: NodePath
@export var camera_path: NodePath
@export var locomotion_path: NodePath

@onready var _label: Label3D = $Label

var _open := false
var _selected := 0
var _repeat_armed := true
var _repeat_timer := 0.0
var _controller: XRController3D
var _camera: XRCamera3D
var _locomotion: Node3D


func _ready() -> void:
	_controller = get_node_or_null(controller_path) as XRController3D
	_camera = get_node_or_null(camera_path) as XRCamera3D
	_locomotion = get_node_or_null(locomotion_path) as Node3D
	visible = false


func is_open() -> bool:
	return _open


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func open() -> void:
	_open = true
	_selected = 0
	_repeat_armed = true
	visible = true
	_place()
	_refresh()
	opened.emit()


func close() -> void:
	_open = false
	visible = false
	closed.emit()


## Put the panel in front of the head, upright, at eye height. Placed once on
## open rather than followed every frame: a panel welded to your face is
## unreadable and unpleasant, and one that stays put can be looked away from.
func _place() -> void:
	if _camera == null:
		return
	var forward := -_camera.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()

	global_position = _camera.global_position + forward * distance
	look_at(global_position + forward, Vector3.UP)


func _process(delta: float) -> void:
	if not _open:
		return

	var stick := _read_stick()
	if absf(stick.y) < stick_threshold:
		_repeat_armed = true
		_repeat_timer = 0.0
	elif _repeat_armed:
		_repeat_armed = false
		_repeat_timer = repeat_delay
		_move_selection(-1 if stick.y > 0.0 else 1)
	else:
		_repeat_timer -= delta
		if _repeat_timer <= 0.0:
			_repeat_timer = repeat_delay
			_move_selection(-1 if stick.y > 0.0 else 1)


func _read_stick() -> Vector2:
	if _controller != null:
		var stick := _controller.get_vector2("primary")
		if stick.length() > 0.1:
			return stick
	return Vector2(0.0, Input.get_axis("ui_down", "ui_up"))


func _move_selection(by: int) -> void:
	_selected = wrapi(_selected + by, 0, ITEMS.size())
	_refresh()


## Act on the highlighted row. Public so the menu can be driven from a
## button press, a test, or the flat-mode keyboard without duplicating it.
func activate() -> void:
	if not _open:
		return
	match ITEMS[_selected]:
		RESUME:
			close()
		RECENTER:
			XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true)
			_place()
		QUIT:
			get_tree().quit()
		_:
			_toggle_setting(ITEMS[_selected])


func _toggle_setting(key: String) -> void:
	var now: bool = not SaveGame.load_setting(key)
	SaveGame.save_setting(key, now)
	# Apply immediately rather than on restart - a comfort toggle you cannot
	# feel the effect of is one you cannot judge.
	if _locomotion != null and _locomotion.has_method("apply_comfort_settings"):
		_locomotion.apply_comfort_settings()
	for node in get_tree().get_nodes_in_group("comfort"):
		if node.has_method("apply_comfort_settings"):
			node.apply_comfort_settings()
	_refresh()


func _refresh() -> void:
	if _label == null:
		return
	var lines: Array[String] = ["- Paused -", ""]
	for i in ITEMS.size():
		var key := ITEMS[i]
		var text: String = LABELS[key]
		if SaveGame.DEFAULTS.has(key):
			text += ":  on" if SaveGame.load_setting(key) else ":  off"
		lines.append(("> %s" if i == _selected else "   %s") % text)
	_label.text = "\n".join(lines)


## What the menu is currently showing, for tests and for anyone wondering
## which row is highlighted without reading the Label3D.
func selected_item() -> String:
	return ITEMS[_selected]
