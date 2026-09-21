extends MeshInstance3D

## Comfort tunnelling. Closes a soft vignette in while the player is being
## moved or turned artificially, and opens it again when they stop.
##
## The single most effective comfort measure for artificial locomotion: what
## makes people ill is peripheral optical flow their inner ear disagrees
## with, so narrowing the periphery exactly while that flow is happening
## removes most of it without taking the movement away.
##
## This is a quad parented to XRCamera3D, so it rides the head and both eyes
## get the same thing. Its shader disables depth test and never writes depth,
## so it draws over the court from wherever the head happens to be.

## Seconds to close in and to open back up. Fading matters: a vignette that
## snaps is its own visual event, which defeats the point.
@export var fade_in := 0.18
@export var fade_out := 0.35
@export var locomotion_path: NodePath

var _enabled := true
var _target := 0.0
var _amount := 0.0
var _material: ShaderMaterial


func _ready() -> void:
	_material = get_active_material(0) as ShaderMaterial
	if _material == null:
		push_warning("Vignette has no ShaderMaterial; comfort tunnelling is off.")
		set_process(false)
		return

	var locomotion := get_node_or_null(locomotion_path)
	if locomotion != null and locomotion.has_signal("motion_changed"):
		locomotion.motion_changed.connect(_on_motion_changed)
	else:
		push_warning("Vignette found no locomotion to follow.")

	apply_comfort_settings()
	_amount = 0.0
	_apply()


## Re-read the setting. Called at startup and whenever the pause menu
## changes it, so a toggle takes effect without a restart.
func apply_comfort_settings() -> void:
	_enabled = SaveGame.load_setting("comfort_vignette")
	if not _enabled:
		_target = 0.0


func _on_motion_changed(moving: bool) -> void:
	_target = 1.0 if (moving and _enabled) else 0.0


func _process(delta: float) -> void:
	if is_equal_approx(_amount, _target):
		return
	# Opening back up is slower than closing in, because the close happens
	# under motion the player asked for and the open should not draw
	# attention to itself.
	var duration := fade_in if _target > _amount else fade_out
	_amount = move_toward(_amount, _target, delta / maxf(duration, 0.001))
	_apply()


func _apply() -> void:
	_material.set_shader_parameter("amount", _amount)
	visible = _amount > 0.001
