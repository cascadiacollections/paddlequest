extends Node3D

## Solo wall bounce: keep the ball off the back of the court. Every clean return
## off the front wall extends the rally and nudges the ball faster.

@export var serve_delay := 1.2
## Re-serve automatically if nothing has been hit for this long, so a stuck
## ball cannot wedge the game.
@export var stall_timeout := 6.0

@onready var _ball: RigidBody3D = $Ball
@onready var _paddle: AnimatableBody3D = $Paddle
@onready var _camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var _label: Label3D = $ScoreLabel
@onready var _miss_zone: Area3D = $MissZone
@onready var _serve_point: Marker3D = $ServePoint
@onready var _wall_target: Marker3D = $WallTarget
@onready var _targets: Node3D = $Targets
@onready var _left: XRController3D = $XROrigin3D/LeftHand
@onready var _right: XRController3D = $XROrigin3D/RightHand

var _rally := 0
var _best := 0
var _points := 0
var _in_play := false
var _xr := false
var _since_progress := 0.0
## Bumped on every serve so a queued serve that has been superseded by a manual
## reset does not fire a second ball.
var _serve_token := 0


func _ready() -> void:
	_xr = XRBoot.start(get_viewport())
	_paddle.set_flat_mode(not _xr)
	if not _xr:
		# XRCamera3D is only driven by the headset, so place it by hand and make
		# it current when we are running flat.
		_camera.position = Vector3(0.0, 1.6, 0.0)
		_camera.current = true

	_ball.assist_target = _paddle
	_ball.wall_hit.connect(_on_wall_hit)
	_ball.paddle_hit.connect(_on_paddle_hit)
	_miss_zone.body_entered.connect(_on_miss)
	_targets.target_hit.connect(_on_target_hit)
	_left.button_pressed.connect(_on_button)
	_right.button_pressed.connect(_on_button)

	_best = SaveGame.load_best()
	_refresh_label("Swing to start")
	_queue_serve()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _xr:
		get_tree().quit()
	elif event.is_action_pressed("ui_accept"):
		_serve()


func _on_button(button: String) -> void:
	if button in ["ax_button", "by_button", "menu_button"]:
		_serve()


func _process(delta: float) -> void:
	if not _in_play:
		return
	_since_progress += delta
	if _since_progress > stall_timeout:
		_refresh_label("Stuck - reserving")
		_queue_serve()


func _queue_serve() -> void:
	_in_play = false
	_serve_token += 1
	var token := _serve_token
	await get_tree().create_timer(serve_delay).timeout
	if token == _serve_token:
		_serve()


func _serve() -> void:
	_serve_token += 1
	_rally = 0
	_in_play = true
	_since_progress = 0.0
	# ball.serve() resets its own speed ceiling; it is not ours to poke.
	_ball.serve(_serve_point.global_position, _wall_target.global_position)
	_refresh_label()


func _on_wall_hit(rally: int) -> void:
	_rally = rally
	if _rally > _best:
		_best = _rally
		# Written on improvement rather than on a timer or at exit: a headset
		# app is closed by taking it off, and there is no shutdown to hook.
		SaveGame.save_best(_best)
	_since_progress = 0.0
	_refresh_label()


func _on_paddle_hit(_impact: float) -> void:
	_since_progress = 0.0
	_paddle.pulse()


func _on_target_hit(bonus: int) -> void:
	_points += bonus
	_since_progress = 0.0
	_refresh_label()


func _on_miss(body: Node3D) -> void:
	if not _in_play or body != _ball:
		return
	_refresh_label("Miss!")
	_queue_serve()


func _refresh_label(message := "") -> void:
	if message != "":
		_label.text = "%s\nbest  %d\n%d pts" % [message, _best, _points]
	else:
		_label.text = "rally  %d\nbest  %d\n%d pts" % [_rally, _best, _points]
