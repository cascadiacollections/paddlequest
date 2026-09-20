extends Node3D

## Glowing panels on the front wall. Hitting one is worth bonus points; it then
## goes dark and reappears elsewhere, so the wall always has something new to
## aim at rather than being a flat backboard.

signal target_hit(bonus: int)

@export var bonus := 5
@export var respawn_delay := 1.2
## Vertical band the panels move within, kept around rally height.
@export var height_range := Vector2(0.85, 1.9)

## Each panel gets its own horizontal band so they cannot land on top of
## each other.
const BANDS: Array[Vector2] = [
	Vector2(-2.1, -0.8),
	Vector2(-0.6, 0.6),
	Vector2(0.8, 2.1),
]

var _areas: Array[Area3D] = []


func _ready() -> void:
	for child in get_children():
		var area := child as Area3D
		if area == null:
			continue
		var index := _areas.size()
		_areas.append(area)
		area.body_entered.connect(_on_area_entered.bind(area, index))
		_relocate(area, index)


func _on_area_entered(body: Node3D, area: Area3D, index: int) -> void:
	if body is not RigidBody3D or not area.monitoring:
		return

	# Deferred: Godot refuses to change monitoring from inside the physics
	# callback that the signal fires in.
	area.set_deferred("monitoring", false)
	area.visible = false
	target_hit.emit(bonus)

	await get_tree().create_timer(respawn_delay).timeout
	if not is_instance_valid(area):
		return
	_relocate(area, index)
	area.visible = true
	area.set_deferred("monitoring", true)


func _relocate(area: Area3D, index: int) -> void:
	var band: Vector2 = BANDS[index % BANDS.size()]
	area.position = Vector3(
		randf_range(band.x, band.y),
		randf_range(height_range.x, height_range.y),
		area.position.z
	)
