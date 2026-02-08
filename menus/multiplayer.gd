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
	$RaceEntrySpawner.spawn_function = _spawn_race_entry
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
		# Periodically check for running games, and push updated list to connected peers.
		$GameRefreshTimer.start()


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
@rpc("any_peer","reliable")
func _server_request_join_game (index: int) -> void:
	var peer_id: int = multiplayer.get_remote_sender_id()
	var game: Game = get_node("game_"+str(index))
	if game == null: return
	_spawn_game.rpc_id (peer_id, index, game.manager_id)

# Create an instance of a running game, and set up multiplayer functionality.
@rpc("authority","call_local","reliable")
func _spawn_game (index: int, manager_id: int) -> void:
	var game: Game = load("res://game.tscn").instantiate()
	game.name = "game_"+str(index)
	add_child(game)
	# Hide game list while connecting to game, to avoid weird things like player being
	# able to click on the "Join" button into their own race that they're already starting.
	$MarginContainer/CenterContainer/VBoxContainer/ScrollContainer/VBoxContainer.hide()
	# Wait until WebRTC is available.
	if not game.get_node("AutoWebRTC").rtc_ready:
		await game.get_node("AutoWebRTC").rtc_ready_signal
	$MarginContainer/CenterContainer/VBoxContainer/ScrollContainer/VBoxContainer.show()
	# Clean up server instance if nobody connected to the game.
	if DisplayServer.get_name() == "headless":
		game.multiplayer.multiplayer_peer.peer_disconnected.connect( func (_peer_id) -> void:
			if len(game.multiplayer.multiplayer_peer.get_peers()) == 0:
				game.queue_free()
		)
	# Set up game management.
	if multiplayer.get_unique_id() == 1:
		print ("Setting manager_id to ", manager_id)
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
		# Defer the process mode change, so we don't pick up the escape key if it
		# was just pressed to exit another menu.
		set_deferred('process_mode',Node.PROCESS_MODE_INHERIT)
	print (multiplayer.get_unique_id(), " RETURNING")
	game.queue_free()


# Called when a new line is added to the list of available races.
# Where is race id going to be stored?
func _spawn_race_entry (id: String):
	var entry = load("res://menus/multiplayer_join_line.tscn").instantiate()
	entry.get_node("JoinButton").pressed.connect(func ():
		if len(_handle.text) == 0:
			$NameWarning.show()
			return
		$NameWarning.hide()
		_server_request_join_game.rpc_id(1, int(id))
	)
	entry.name = id
	return entry

func _on_game_refresh_timer_timeout() -> void:
	var vbox: VBoxContainer = $MarginContainer/CenterContainer/VBoxContainer/ScrollContainer/VBoxContainer
	var valid_games: Array[String]
	for game_ in get_children():
		if game_ is not Game: continue
		var game: Game = game_
		var participants: Array[String] = []
		for p in game.get_node("CarSelection").participants.values():
			participants.append(p[0])  # (handle, car)
		var host: String = game.get_node("CarSelection").participants.get(game.manager_id,["",null])[0]
		var id: String = game.name.split('_')[1]
		if not vbox.has_node(id):
			$RaceEntrySpawner.spawn(id)
		var entry: MultiplayerJoinLine = vbox.get_node(id)
		entry.update_race(host, participants, game.track_name)
		valid_games.append(id)
	# Clean up invalid / completed games.
	for entry in vbox.get_children():
		if entry is MultiplayerJoinLine and entry.name not in valid_games:
			entry.queue_free()
	# Show message if no races available.
	if len(valid_games) == 0:
		$MarginContainer/CenterContainer/VBoxContainer/ScrollContainer/VBoxContainer/NoRacesLabel.visible = true
	else:
		$MarginContainer/CenterContainer/VBoxContainer/ScrollContainer/VBoxContainer/NoRacesLabel.visible = false
