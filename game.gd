extends Control

class_name Game

## Cars that start off as locked in single player game.
@export var locked_cars: Array[String] = []

# The peer who is managing this game (for multiplayer games).
var manager_id: int = 1

# Lookup table of the handles of peers connected to the game.
# Available to the server instance only, not clients.
#var handles: Dictionary[int,String] = {}


# Set the manager for the game.
# Only needs to be done once.
func setup (manager: int) -> void:
	assert (multiplayer.get_unique_id() == 1)
	manager_id = manager
	$TrackSelection.setup(manager_id)
	$CarSelection.setup(manager_id, locked_cars)

func _ready() -> void:
	$RaceSpawner.spawn_function = _spawn_race
	if multiplayer.multiplayer_peer is not OfflineMultiplayerPeer and multiplayer.get_unique_id() == 1:
		multiplayer.peer_disconnected.connect(peer_disconnected)

func run (handle: String) -> void:
	print ('?? ', multiplayer.multiplayer_peer)
	print ("Running ", name, " from peer ", multiplayer.get_unique_id())
	show()
	while true:
		# Track selection
		var track_name: String = await $TrackSelection.run()
		print ("Track selected: '"+track_name+"'")
		if track_name == "": break
		var track: Track = load("res://tracks/%s.tscn"%track_name).instantiate()
		# Character selection
		var participants: Dictionary = await $CarSelection.run(handle)
		if len(participants) == 0: break
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
		var place: int = await race.run(participants)
		remove_child(race)
		if place <= 0: break
		# Conclusion (e.g. unlocking new cars, etc.)
		_race_ended(track_name, place)
		# Back to track selection
	hide()


#TODO: remove
@rpc("any_peer","call_local","reliable")
func _server_request_race (race_id: int, track_name: String, participants: Dictionary) -> void:
	var _running_races: Array
	var race_name: String = "race_"+str(race_id)
	var race: World
	# If this wasn't called by the host, and the host hasn't requested the race object yet, then
	# wait until it's ready.
	if track_name == "" and not has_node(race_name):
		print ("Waiting for host to initiate race")
		#await _race_ready
		#TODO
	if has_node(race_name):
		race = get_node(race_name)
	else:
		# Construct a list of all race participants, starting with the host.
		var player_ids: Array[int] = [race_id]
		for player_id in participants.keys():
			if player_id not in player_ids:
				player_ids.append(player_id)
		# Find a free index for the race.
		# Starting at index 1 instead of 0, to always start in an offset.
		# (avoids visual glitches where things spawn starting at the origin).
		var index: int = 1
		while index in _running_races:
			index += 1
		# Spawn the race
		race = $RaceSpawner.spawn([index,race_id,player_ids,"res://tracks/%s.tscn"%track_name])
		var player_names: Array[String] = []
		for player_id in participants.keys():
			player_names.append(participants[player_id][0])
		print ("Starting race ", race_id, " at index ", index, " with players ", "," .join(player_names), ".")
		_running_races[index] = race
		# Free the race object once all players have left the game.
		race.tree_exited.connect(func () -> void:
			print ("Finished race ", race_id)
			_running_races.erase(index)
		)
		# Run from server side as well (which will control the race).
		if multiplayer.multiplayer_peer is not OfflineMultiplayerPeer:
			race.run(participants)

# This is called to create a multiplayer race among all peers.
# "data" is the race_id, and dictionary containing all players / karts for the race.
func _spawn_race (data: Array) -> Node:
	var race: Node
	var index: int = data[0]
	var track_scene_path: String = data[1]

	race = load("res://world.tscn").instantiate()
	# Each race is offset so that they don't overlap in the coordinate space.
	# So that rigid bodies from different races don't collide with each other... haha.
	race.global_position.x = 100000*index
	var track: Track = load(track_scene_path).instantiate()
	# Need to defer call to this, otehrwise the itemblocks don't show up as children and don't get set up?
	track.call_deferred('setup')
	race.set_track(track)

	# Set a consistent name for this race across all peers.
	race.name = "race_"+str(index)

	# If this is a local game, then we have everything we need.
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return race

	#TODO
	var player_id = null

	# Prepare an RTC connection for this race.

	# First, use a unique MultiplayerAPI for the race (so the communication is only performed
	# for the participating racers.
	var multiplayer_path: NodePath = NodePath("/root/TitleScreen/"+race.name)
	if get_tree().get_multiplayer(multiplayer_path) == multiplayer:
		#print ("Setting independent multiplayer API for ", race.name)
		get_tree().set_multiplayer(SceneMultiplayer.new(), multiplayer_path)

	# Next, make sure a WebRTCMultiplayerPeer is created once the race is in the tree.
	# Create in server mode for the server, and client mode for the client.
	# (not using fully connected mesh of peers, everything will be using client/server model for simplicity).
	if player_id == 1:
		race.tree_entered.connect( func () -> void:
			var rtc: WebRTCMultiplayerPeer = WebRTCMultiplayerPeer.new()
			rtc.create_server()
			race.multiplayer.multiplayer_peer = rtc
			#print ("Server peer created.")
		)
	else:
		race.tree_entered.connect( func () -> void:
			var rtc: WebRTCMultiplayerPeer = WebRTCMultiplayerPeer.new()
			# Use same unique peer id as the WebSocket connection, for consistency.
			rtc.create_client(player_id)
			race.multiplayer.multiplayer_peer = rtc
			#print ("Client peer created.")
		)

	# Clean up MultiplayerAPI objects once the race is completed.
	race.tree_exiting.connect( func () -> void:
		#print ("Removing independent multiplayer API for ", race.name)
		get_tree().set_multiplayer(null, race.get_path())
	)

	return race


# Called at conclusion of race
func _race_ended (_track_name: String, _place: int) -> void:
	pass


# Called when a peer has disconnected from the race (called on server in multiplayer mode).
func peer_disconnected(_peer_id: int):
	pass #TODO
