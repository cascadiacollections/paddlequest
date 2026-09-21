class_name SaveGame
extends RefCounted

## Persisted progress. Small enough that ConfigFile is the right tool: it is
## text, it is diffable if anyone ever needs to look, and it fails soft.
##
## Nothing here is allowed to throw. A save file is the one piece of state the
## player did not consent to and cannot repair, so a missing, unreadable or
## garbled one reads as a fresh start rather than an error - losing a high
## score is a disappointment, refusing to launch is a bug report.

const PATH := "user://progress.cfg"
const SECTION := "progress"
const BEST_KEY := "best_rally"


## Best rally ever recorded, or 0 if there is nothing usable on disk.
static func load_best(path: String = PATH) -> int:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		# Absent on a first run, unreadable if the file was truncated or is
		# not ConfigFile at all. Both mean the same thing to us.
		return 0

	var stored: Variant = config.get_value(SECTION, BEST_KEY, 0)
	# A hand-edited file can put anything here, including a string or a
	# dictionary. Anything that is not a sane count is not a high score.
	if not (stored is int or stored is float):
		return 0
	var best := int(stored)
	return best if best > 0 else 0


## Write `best` if it beats what is already stored. Returns whether it wrote.
static func save_best(best: int, path: String = PATH) -> bool:
	if best <= load_best(path):
		return false

	var config := ConfigFile.new()
	# Load first so an unrelated key added later is not dropped on the way
	# through. A failure here is fine: we are about to write the file anyway.
	config.load(path)
	config.set_value(SECTION, BEST_KEY, best)
	if config.save(path) != OK:
		push_warning("Could not write %s; the high score will not persist." % path)
		return false
	return true
