extends Control

@onready var _handle: LineEdit = $MarginContainer/CenterContainer/VBoxContainer/HBoxContainer2/Handle

func run() -> void:
	# Connect to the WebSocket server.
	multiplayer.multiplayer_peer = null
	var peer := WebSocketMultiplayerPeer.new()
	if "--local" in OS.get_cmdline_user_args():
		peer.create_client("ws://localhost:1157")
	else:
		peer.create_client("wss://nasercar.mikeasaurus.ca:1158")
	multiplayer.multiplayer_peer = peer
	show()
	# Disconnect after player is done with multiplayer mode.
	await $MarginContainer/CenterContainer/VBoxContainer/HBoxContainer/BackButton.pressed
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	hide()
	return

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# If this is configured as a headless server, then set up the connection.
	if DisplayServer.get_name() == "headless":
		# Set up server, listening for incoming peers.
		multiplayer.multiplayer_peer = null
		#multiplayer.peer_disconnected.connect(_on_client_disconnected)
		var peer := WebSocketMultiplayerPeer.new()
		if "--local" in OS.get_cmdline_user_args():
			peer.create_server(1157)
		else:
			#NOTE: remote server should be run with the command-line option --headless
			# (Need to run without a display)
			var key := load("res://cert/privkey.key")
			var cert := load("res://cert/fullchain.crt")
			var tls_options := TLSOptions.server(key,cert)
			peer.create_server(1158,"*",tls_options)
		multiplayer.multiplayer_peer = peer


# Player wants to start their own multiplayer session.
func _on_new_button_pressed() -> void:
	if len(_handle.text) == 0:
		$NameWarning.show()
		return
	$NameWarning.hide()
	_server_request_new_game.rpc_id(1)
@rpc("any_peer","reliable")
func _server_request_new_game () -> void:
	# Find an available index for the game.
	var index: int = 1
	while has_node("game_"+str(index)): index += 1
	# The client who requested the new game will control the settings.
	var manager_id: int = multiplayer.get_remote_sender_id()
	# Spawn and launch an instance of the game on this end (server).
	_spawn_game.rpc_id (1, index, manager_id)
	# Spawn and launch an instance on the client side.
	_spawn_game.rpc_id (manager_id, index, manager_id)

# Create an instance of a running game, and set up multiplayer functionality.
@rpc("authority","call_local","reliable")
func _spawn_game (index: int, manager_id: int) -> void:
	var game: Game = Game.new()
	game.name = "game_"+str(index)

	# The peer where this function is running.
	var peer_id: int = multiplayer.get_unique_id()

	# Prepare an RTC connection for this race.

	# First, use a unique MultiplayerAPI for the race (so the communication is only performed
	# for the participating racers.
	var multiplayer_path: NodePath = NodePath("/root/TitleScreen/Multiplayer/"+game.name)
	if get_tree().get_multiplayer(multiplayer_path) == multiplayer:
		print ("Setting independent multiplayer API for ", game.name)
		get_tree().set_multiplayer(SceneMultiplayer.new(), multiplayer_path)

	# Next, make sure a WebRTCMultiplayerPeer is created once the race is in the tree.
	# Create in server mode for the server, and client mode for the client.
	# (not using fully connected mesh of peers, everything will be using client/server model for simplicity).
	var rtc: WebRTCMultiplayerPeer = WebRTCMultiplayerPeer.new()
	# Establish WebRTC connection (pass SDP / ICE information)
	var connection: WebRTCPeerConnection = WebRTCPeerConnection.new()
	if peer_id == 1:
		game.tree_entered.connect( func () -> void:
			# Make sure WebRTC is set up for this game (not using WebSocket manager).
			assert (game.multiplayer.multiplayer_peer != game.get_parent().multiplayer.multiplayer_peer)
			rtc.create_server()
			game.multiplayer.multiplayer_peer = rtc
			print ("Server peer created.")
###
			connection.session_description_created.connect( func (type: String, sdp: String) -> void:
				#print ("SERVER SIDE SDP CREATED")
				connection.set_local_description(type, sdp)
				add_server_sdp.rpc_id(peer_id, game.name, type, sdp)
			)
			connection.ice_candidate_created.connect( func (media: String, ice_index: int, name_arg: String) -> void:
				#print ("SERVER SIDE ICE CANDIDATE CREATED")
				add_server_ice.rpc_id(peer_id, game.name, media, ice_index, name_arg)
			)
			game.multiplayer.multiplayer_peer.add_peer(connection, peer_id)
			#print ("CREATING OFFER")
			connection.create_offer()
###
		)
	else:
		game.tree_entered.connect( func () -> void:
			# Make sure WebRTC is set up for this game (not using WebSocket manager).
			assert (game.multiplayer.multiplayer_peer != game.get_parent().multiplayer.multiplayer_peer)
			# Use same unique peer id as the WebSocket connection, for consistency.
			rtc.create_client(peer_id)
			game.multiplayer.multiplayer_peer = rtc
			print ("Client peer created.")
###
			connection.session_description_created.connect( func (type: String, sdp: String) -> void:
				#print ("CLIENT SIDE SDP CREATED")
				connection.set_local_description(type, sdp)
				add_client_sdp.rpc_id(1, game.name, type, sdp)
			)
			connection.ice_candidate_created.connect(func (media: String, ice_index: int, name_arg: String) -> void:
				#print ("CLIENT SIDE ICE CREATED")
				add_client_ice.rpc_id(1, game.name, media, ice_index, name_arg)
			)
###
		)
	# Clean up MultiplayerAPI objects once the race is completed.
	game.tree_exiting.connect( func () -> void:
		#print ("Removing independent multiplayer API for ", race.name)
		get_tree().set_multiplayer(null, game.get_path())
	)

	rtc.add_peer(connection, 1)


	# Launch the multiplayer game.
	add_child(game)
	await game.run(index, manager_id, _handle.text)
	remove_child(game)

# Update list of races available.
func _server_update_list () -> void:
	for c in get_children():
		if c is Game:
			pass #TODO

# This function is called to refresh the list of races.
func update_race (race_id: int, track_name: String, participants: Dictionary) -> void:
	var available_races: Dictionary
	# If this is a new race, then add it to the list.
	if race_id not in available_races:
		available_races[race_id] = $RaceEntrySpawner.spawn(race_id)
		var handle: String = "Someone"
		# Get race host.
		if race_id in participants: handle = participants[race_id][0]
		available_races[race_id].get_node("VBoxContainer/Host").text = "%s is starting a new race"%handle
	var entry: Node = available_races[race_id]
	# Update number of participants.
	entry.get_node("VBoxContainer/NumPlayers").text = "Track: \"%s\"   %d player(s) joined so far"%[track_name, len(participants)]
	# If an empty list of participants was given, then the race is not available to join anymore.
	if len(participants) == 0:
		available_races.erase(race_id)
		entry.queue_free()
	# If no races available, then show a message.
	if len(available_races) == 0:
		$MarginContainer/CenterContainer/VBoxContainer/ScrollContainer/VBoxContainer/NoRacesLabel.show()
	else:
		$MarginContainer/CenterContainer/VBoxContainer/ScrollContainer/VBoxContainer/NoRacesLabel.hide()

# Called when a new line is added to the list of available races.
# Where is race id going to be stored?
func _spawn_race_entry (id: int):
	var entry = load("res://menus/multiplayer_join_line.tscn").instantiate()
	entry.get_node("JoinButton").pressed.connect(func ():
		if len(_handle.text) == 0:
			$NameWarning.show()
			return
		$NameWarning.hide()
		#_done.emit(id,_handle.text)
	)
	entry.name = str(id)
	return entry



# Use these WebSocket-backed RPC functions for mediating the creation of WebRTC connections for the multiplayer races.

@rpc("any_peer","reliable")
func add_client_sdp (game_name: String, type: String, sdp: String) -> void:
	#print ("ADDING CLIENT SDP for ", game_name, ": ", type, " :: ", sdp)
	var peer_id: int = multiplayer.get_remote_sender_id()
	var rtc: WebRTCMultiplayerPeer = get_node(game_name).multiplayer.multiplayer_peer
	var connection: WebRTCPeerConnection = rtc.get_peer(peer_id)['connection']
	connection.set_remote_description(type, sdp)
@rpc("any_peer","reliable")
func add_client_ice (game_name: String, media: String, index: int, name_arg: String) -> void:
	#print ("ADDING CLIENT ICE for ", game_name, ": ", media, " :: ", index, " :: ", name_arg)
	var peer_id: int = multiplayer.get_remote_sender_id()
	var rtc: WebRTCMultiplayerPeer = get_node(game_name).multiplayer.multiplayer_peer
	var connection: WebRTCPeerConnection = rtc.get_peer(peer_id)['connection']
	connection.add_ice_candidate(media, index, name_arg)

@rpc("authority","reliable")
func add_server_sdp (game_name: String, type: String, sdp: String) -> void:
	#print ("ADDING SERVER SDP for ", game_name, ": ", type, " :: ", sdp)
	var rtc: WebRTCMultiplayerPeer = get_node(game_name).multiplayer.multiplayer_peer
	var connection: WebRTCPeerConnection = rtc.get_peer(1)['connection']
	connection.set_remote_description(type, sdp)
@rpc("authority","reliable")
func add_server_ice (game_name: String, media: String, index: int, name_arg: String) -> void:
	#print ("ADDING SERVER ICE for ", game_name, ": ", media, " :: ", index, " :: ", name_arg)
	var rtc: WebRTCMultiplayerPeer = get_node(game_name).multiplayer.multiplayer_peer
	var connection: WebRTCPeerConnection = rtc.get_peer(1)['connection']
	connection.add_ice_candidate(media, index, name_arg)
