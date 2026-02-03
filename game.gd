extends Control

class_name Game

# NOTE: Most (if not all) attributes here are defined on server side / local only,
# and delegated to clients through appropriate RPC functions.

## Cars that start off as locked in single player game.
@export var locked_cars: Array[String] = []

# The peer who is managing this game (for multiplayer games).
var manager_id: int = 1

# The name of the current track (once selected).
var track_name: String = ""

# Set the manager for the game.
# Only needs to be done once.
func setup (manager: int) -> void:
	assert (multiplayer.get_unique_id() == 1)
	manager_id = manager
	$TrackSelection.setup(manager_id, $CarSelection.participants)
	$CarSelection.setup(manager_id, locked_cars)

func _ready() -> void:
	if multiplayer.multiplayer_peer is not OfflineMultiplayerPeer and multiplayer.get_unique_id() == 1:
		multiplayer.peer_disconnected.connect(peer_disconnected)

func run (handle: String) -> void:
	print ("Running ", name, " from peer ", multiplayer.get_unique_id())
	show()
	var status_ok: bool = true
	# Character selection (for players)
	if DisplayServer.get_name() != "headless":
		status_ok = await $CarSelection.run(handle)
	while status_ok:
		# Track selection
		track_name = ""
		track_name = await $TrackSelection.run()
		print ("Track selected: '"+track_name+"'")
		if track_name == "": break
		var track: Track = load("res://tracks/%s.tscn"%track_name).instantiate()
		# Race
		var race: World = load("res://world.tscn").instantiate()
		# Offset the race from origin so it doesn't collide with other races.
		# (for multiplayer races).
		var index: int = 1
		if '_' in name:
			index = int(name.split('_')[1])
		race.global_position.x = 100000*index
		race.set_track(track)
		add_child(race)
		var place: int = await race.run($CarSelection.participants)
		remove_child(race)
		if place <= 0: break
		# Conclusion (e.g. unlocking new cars, etc.)
		await _race_ended(track_name, place)
		# Back to track selection
		break #TODO
	hide()


# Called at conclusion of race
func _race_ended (_track_name: String, _place: int) -> void:
	pass


# Called when a peer has disconnected from the race (called on server in multiplayer mode).
func peer_disconnected(_peer_id: int):
	pass #TODO
