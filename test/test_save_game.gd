extends GutTest

## A save file is the one piece of state the player did not consent to and
## cannot repair by hand, so every failure path here has to read as "fresh
## start" rather than throw. Losing a high score is a disappointment;
## refusing to launch is a bug report.

const TMP := "user://test_progress.cfg"


func before_each() -> void:
	_remove()


func after_each() -> void:
	_remove()


func _remove() -> void:
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


func _write(contents: String) -> void:
	var file := FileAccess.open(TMP, FileAccess.WRITE)
	assert_not_null(file, "should be able to write the fixture")
	file.store_string(contents)
	file.close()


func test_a_missing_file_reads_as_zero() -> void:
	assert_eq(SaveGame.load_best(TMP), 0, "a first run has no high score")


func test_a_score_survives_a_round_trip() -> void:
	assert_true(SaveGame.save_best(12, TMP), "a first score should be written")
	assert_eq(SaveGame.load_best(TMP), 12, "the score should come back")


func test_a_worse_score_does_not_overwrite_a_better_one() -> void:
	SaveGame.save_best(12, TMP)
	assert_false(SaveGame.save_best(5, TMP), "a worse score should not be written")
	assert_eq(SaveGame.load_best(TMP), 12, "the better score should survive")


func test_an_equal_score_is_not_rewritten() -> void:
	SaveGame.save_best(12, TMP)
	assert_false(SaveGame.save_best(12, TMP), "matching the record is not beating it")


func test_a_garbled_file_reads_as_zero() -> void:
	_write("this is not a ConfigFile at all\x00\x01")
	assert_eq(SaveGame.load_best(TMP), 0, "an unparseable file should read as a fresh start")


func test_a_file_of_the_wrong_shape_reads_as_zero() -> void:
	# Valid ConfigFile, wrong type in the slot - what a hand edit produces.
	_write('[progress]\nbest_rally="not a number"\n')
	assert_eq(SaveGame.load_best(TMP), 0, "a non-numeric score is not a score")


func test_a_negative_score_reads_as_zero() -> void:
	_write("[progress]\nbest_rally=-5\n")
	assert_eq(SaveGame.load_best(TMP), 0, "a negative rally count is not a score")


func test_saving_keeps_unrelated_keys() -> void:
	# Later settings will live in this file too; writing a score must not
	# drop them.
	_write("[progress]\nbest_rally=3\n\n[settings]\ncomfort_vignette=false\n")
	SaveGame.save_best(9, TMP)

	var config := ConfigFile.new()
	assert_eq(config.load(TMP), OK, "the file should still parse")
	assert_eq(config.get_value("settings", "comfort_vignette"), false, "unrelated key kept")
	assert_eq(config.get_value("progress", "best_rally"), 9, "score updated")
