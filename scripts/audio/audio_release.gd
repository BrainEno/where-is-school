class_name AudioRelease
extends RefCounted
## Stopping a sound and having it gone are two steps in Godot, and quitting can come between
## them (#67).
##
## A player's `stop()` (or its being freed) only marks its playback for removal. The audio
## thread takes it off the server's list on its next mix, a few tens of milliseconds later,
## and the main thread frees it at its next audio update - or when the audio server is
## destroyed, which at quit still happens before the engine counts leaked objects. What
## quitting skips is the mix: the scene tree is freed and the audio driver stopped
## (`AudioServer::finish()`) right after, and a playback the driver never mixed again is
## never taken off the list. Every headless check ended with "2 ObjectDB instances were
## leaked at exit" that way: a playback, and the stream it held.
##
## So whatever plays sound and is freed at quit waits here for one mix after its stop. The
## wait is bounded, and short when the driver runs: about 23 ms at the dummy driver's
## 1024 frames / 44.1 kHz. Nothing is filtered out of a log; the playback is let go.

## The longest a wait lasts. Past it the driver is not mixing, and waiting longer would not
## help: the caller says so (verbose output) and the engine's own leak warning follows.
const TIMEOUT_MSEC := 250
const POLL_MSEC := 2


## Stops every player in `players` (`AudioStreamPlayer`, `...2D`, `...3D`; anything else is
## skipped) and returns how many had a playback to hand back - 0 means there is nothing to
## wait for.
static func stop_all(players: Array) -> int:
	var stopped := 0
	for entry: Variant in players:
		# Checked before the cast: casting a freed object is an error of its own.
		if not is_instance_valid(entry):
			continue
		var node := entry as Node
		if node == null or not node.has_method("has_stream_playback"):
			continue
		if bool(node.call("has_stream_playback")):
			stopped += 1
		node.call("stop")
	return stopped


## Waits, on the calling thread and at most `timeout_msec`, until the audio thread has
## started a mix after this call and finished it. Returns whether it did. Every playback
## stopped before the call is off the server's list by then.
static func wait_for_mix(timeout_msec: int = TIMEOUT_MSEC) -> bool:
	var since_usec := Time.get_ticks_usec()
	var deadline := Time.get_ticks_msec() + maxi(timeout_msec, 0)
	while not mixed_since(since_usec):
		if Time.get_ticks_msec() >= deadline:
			return false
		OS.delay_msec(POLL_MSEC)
	return true


## Whether a mix has started since `usec` (`Time.get_ticks_usec()`) and finished. The driver
## stamps the start of each mix under its lock, and reading the stamp takes the same lock,
## so a mix in progress ends before this returns. `now` is read first, which can only make
## the stamp look earlier than it was, never later.
static func mixed_since(usec: int) -> bool:
	var now := Time.get_ticks_usec()
	var since := AudioServer.get_time_since_last_mix()
	return now - int(since * 1000000.0) > usec
