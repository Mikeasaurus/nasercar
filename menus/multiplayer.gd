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
	# Allow user to immediately type out their nickname.
	$MarginContainer/CenterContainer/VBoxContainer/HBoxContainer2/Handle.grab_focus()
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
func _on_handle_text_submitted(_new_text: String) -> void:
	_on_new_button_pressed()
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
	var game: Game = load("res://game.tscn").instantiate()
	game.name = "game_"+str(index)
	add_child(game)
	# Wait until WebRTC is available.
	if not game.get_node("AutoWebRTC").rtc_ready:
		await game.get_node("AutoWebRTC").rtc_ready_signal
	print ("Setting manager_id to ", manager_id)
	if multiplayer.get_unique_id() == 1:
		game.setup(manager_id)
	# Launch the multiplayer game.
	# Disable the controls for this screen, so they don't interfere with the game.
	# Otherwise, things like escape key would trigger the 'Back' button from here.
	# (Keep running on server instance, though, because otherwise server stops working haha)
	if multiplayer.get_unique_id() != 1:
		process_mode = Node.PROCESS_MODE_DISABLED
	await game.run(_handle.text)
	# Resume this interface after race is finished.
	if multiplayer.get_unique_id() != 1:
		process_mode = Node.PROCESS_MODE_INHERIT
	print (multiplayer.get_unique_id(), " RETURNING")
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
