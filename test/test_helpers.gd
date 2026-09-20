class_name PaddleTest
extends GutTest

## Shared rig for the integration tests. These drive the real main scene rather
## than mocks, because every regression this suite exists for came from parts
## interacting: a serve that ignored gravity, a ball that could not escape a
## vertical loop, render settings applied at the wrong point in a lifecycle.

const MAIN := preload("res://scenes/main.tscn")

const WALL_Z := -6.1
const PHYSICS_HZ := 90.0

var main: Node3D
var ball: RigidBody3D
var game: Node3D


func build_scene() -> void:
	main = MAIN.instantiate()
	add_child_autofree(main)
	game = main
	ball = main.get_node("Ball")
	await step(2)


## Advance a fixed number of physics frames.
func step(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func seconds(t: float) -> int:
	return int(ceil(t * PHYSICS_HZ))


## Run until `check` is true or we run out of frames. Returns whether it hit.
func step_until(check: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if check.call():
			return true
		await get_tree().physics_frame
	return check.call()


func label_text() -> String:
	return (main.get_node("ScoreLabel") as Label3D).text


func rally() -> int:
	for line in label_text().split("\n"):
		if line.begins_with("rally"):
			return int(line.replace("rally", "").strip_edges())
	return -1


## Wait for the ball to actually be served. Waiting on velocity is not enough:
## the ball satisfies that immediately by falling under gravity.
func await_serve() -> void:
	var served := await step_until(func(): return rally() >= 0, seconds(6.0))
	assert_true(served, "ball should be served")


## Wait until the ball has come off the front wall once. The speed floor stays
## off until the ball is genuinely in play, so tests about it must get here.
func await_first_wall_hit() -> void:
	await await_serve()
	var hit := await step_until(func(): return rally() >= 1, seconds(6.0))
	assert_true(hit, "ball should reach the front wall")


func points() -> int:
	# "rally  N\nbest  N\nN pts"
	for line in label_text().split("\n"):
		if line.ends_with("pts"):
			return int(line.replace("pts", "").strip_edges())
	return -1
