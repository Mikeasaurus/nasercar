extends Control

## Cars that start off as locked in single player game.
@export var locked_cars: Array[String] = ["Naomi"]

# Table of currently running races.
# (also for server side).
# Key is race number, values are the nodes containing the races.
var _running_races: Dictionary = {}

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var notracks: Array[TileMapLayer] = []
	$NaserCar.add_to_track($Path2D,notracks)
	$NaserCar.make_local_cpu()
	_reset_and_start_timer()
	# If this is configured as a headless server, then set up the connection.
	if DisplayServer.get_name() == "headless":
		_make_server()
	# Spawn a race in multiplayer context.
	$CarSelectionMenuSpawner.spawn_function = _spawn_car_selection_menu
	$RaceSpawner.spawn_function = _spawn_race

# Multiplayer server setup.
func _make_server () -> void:
	# Set up server, listening for incoming peers.
	multiplayer.multiplayer_peer = null
	#multiplayer.peer_disconnected.connect(_on_client_disconnected)
	var peer := WebSocketMultiplayerPeer.new()
	if "--local" in OS.get_cmdline_user_args():
		peer.create_server(1157)
	else:
		#NOTE: remote server should be run with the command-line options --headless --max-fps=45
		# Need to run without a display, and also limit the fps to avoid excessive
		# jitter when syncing game state via Websocket/TCP.
		var key := load("res://cert/privkey.key")
		var cert := load("res://cert/fullchain.crt")
		var tls_options := TLSOptions.server(key,cert)
		peer.create_server(1157,"*",tls_options)
	multiplayer.multiplayer_peer = peer
	# Turn off the Naser car for server instance, otherwise it gets synchronized to all the players and
	# they see an extra car floating around the screen!
	_reset_car()

func _reset_car() -> void:
	$NaserCar.set_deferred("global_position",Vector2(-53,-75))
	$NaserCar.set_deferred("linear_velocity",Vector2.ZERO)
	$NaserCar.freeze = true
	$NaserCar.show()
	$NaserCar.stop()
	$CarTimer.stop()
func _reset_and_start_timer() -> void:
	_reset_car()
	$CarTimer.start()

func _on_help_pressed() -> void:
	# Hide menu
	$MarginContainer.hide()
	# Start help menu
	await $Help.run()
	# Show the main menu again.
	$MarginContainer.show()

func new_game () -> void:
	# Hide menu
	$MarginContainer.hide()
	var race_id: int
	var handle: String
	# Join a multiplayer race?
	if multiplayer.get_unique_id() != 1:
		var info: Array = await $Multiplayer.run()
		race_id = info[0]
		handle = info[1]
		# Check if player cancelled joining a race.
		if race_id == -1:
			$Multiplayer.hide()
			$MarginContainer.show()
			return
	else:
		race_id = 1
		handle = "Player"
	# If this player is starting the race, then they decide the track to use.
	var track_name: String
	if race_id == multiplayer.get_unique_id():
		track_name = await $TrackSelection.run()
		if track_name == "":
			$Multiplayer.hide()
			$TrackSelection.hide()
			$MarginContainer.show()
			return
	else:
		track_name = ""  # Track name not needed by other peers.
	var selection_menu: CarSelection
	# Now that a track is chosen, launch the car selection menu.
	selection_menu = await _request_car_selection_menu (race_id, track_name)
	# Hide the previous multiplayer menu after this selection menu is available.
	$Multiplayer.hide()
	$TrackSelection.hide()

	# Select a car.
	var participants: Dictionary = await selection_menu.run(handle)

	# Check for error codes.
	if -1 in participants:
		var msg: String = participants[-1]
		participants.erase(-1)
		var e: Label = $MarginContainer/CenterContainer/VBoxContainer/ErrorMessage
		e.modulate = Color.WHITE
		e.text = msg
		var tween: Tween = create_tween()
		tween.tween_interval(3.0)
		tween.tween_property(e,"modulate",Color.hex(0xffffff00),3.0)

	# Set up and run the race.
	if len(participants) > 0:
		var race: World = await _request_race (race_id, track_name, participants)
		# Start race and wait for it to end.
		var place: int = await race.run(participants)
		# Check if a character was unlocked.
		if multiplayer.get_unique_id() == 1 and place == 1 and "Naomi" in locked_cars:
			await $Naomi.run()
			locked_cars.erase("Naomi")
	# If a race wasn't run (e.g. user cancelled at car selection), then need to free
	# the car selection menu here.  It won't be cleaned up by the _request_race logic in this case.
	else:
		selection_menu.queue_free()
	# Show the main menu again.
	$MarginContainer.show()

func _on_single_player_pressed() -> void:
	new_game()

# When multiplayer is clicked, need to start a connection to the server.
func _on_multiplayer_pressed() -> void:
	multiplayer.multiplayer_peer = null
	if not multiplayer.connected_to_server.is_connected(_open_multiplayer_menu):
		multiplayer.connected_to_server.connect(_open_multiplayer_menu)
	var peer := WebSocketMultiplayerPeer.new()
	if "--local" in OS.get_cmdline_user_args():
		peer.create_client("ws://localhost:1157")
	else:
		peer.create_client("wss://nasercar.mikeasaurus.ca:1157")
	multiplayer.multiplayer_peer = peer
# This is called once the server process is established.
func _open_multiplayer_menu() -> void:
	await new_game()
	if multiplayer.multiplayer_peer.get_connection_status() == multiplayer.multiplayer_peer.CONNECTION_CONNECTED:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

func _on_car_timer_timeout() -> void:
	$NaserCar.freeze = false
	$NaserCar.go()

# Get reference to car selection menu.
func _request_car_selection_menu (race_id: int, track: String) -> Node:
	_server_request_car_selection_menu.rpc_id(1,race_id,track)
	var menu_name: String = 'car_selection_'+str(race_id)
	# Quick and dirty way to handle case where rpc call was instantaneous (i.e. local).
	if not has_node(menu_name):
		# If not immediately available, then wait for it.
		# Assuming there's no race condition between these two lines!
		await _car_selection_menu_ready
	return get_node(menu_name)
@rpc("any_peer","call_local","reliable")
func _server_request_car_selection_menu (race_id: int, track: String) -> void:
	var menu_name: String = 'car_selection_'+str(race_id)
	var selection: CarSelection
	if not has_node(menu_name):
		selection = $CarSelectionMenuSpawner.spawn(race_id)
		# If this is a single player game, then respect the locked cars list.
		if multiplayer.get_remote_sender_id() == 1:
			selection.setup(race_id, track, locked_cars)
		else:
			selection.setup(race_id, track, [])
		# Connect a signal that lets the list of participants be updated on the multiplayer menu list.
		#selection.participants_updated.connect($Multiplayer.update_race.bind([race_id]))
		selection.participants_updated.connect(func (participants: Dictionary) -> void:
			$Multiplayer.update_race(race_id, track, participants)
		)
	# Tell client that the menu is available.
	_client_receive_car_selection_menu.rpc_id(multiplayer.get_remote_sender_id())
@rpc("authority","call_local","reliable")
func _client_receive_car_selection_menu () -> void:
	_car_selection_menu_ready.emit()
signal _car_selection_menu_ready

# Spawn a menu for selecting cars within a multiplayer race.
func _spawn_car_selection_menu (race_id: int) -> Node:
	var menu: CarSelection = preload("res://menus/car_selection.tscn").instantiate()
	menu.name = 'car_selection_'+str(race_id)
	# Car selection menu needs to know which player is creating the race.
	# (the race id corresponds to their player id).
	# The creator has control over starting / cancelling the race.
	menu.race_id = race_id
	# Invisible by default (until explicitly made visible by peer).
	menu.visible = false
	return menu

# Get a reference to a race.
# Create it if it doesn't exist yet.
func _request_race (race_id: int, track_name: String, participants: Dictionary) -> World:
	_server_request_race.rpc_id(1,race_id, track_name, participants)
	var race_name: String = "race_"+str(race_id)
	if not has_node(race_name):
		await _race_ready
	return get_node(race_name)
@rpc("any_peer","call_local","reliable")
func _server_request_race (race_id: int, track_name: String, participants: Dictionary) -> void:
	var race_name: String = "race_"+str(race_id)
	# If this wasn't called by the host, and the host hasn't requested the race object yet, then
	# wait until it's ready.
	if track_name == "" and not has_node(race_name):
		print ("Waiting for host to initiate race")
		await _race_ready
	if not has_node(race_name):
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
		var race: World = $RaceSpawner.spawn([index,race_id,player_ids,"res://tracks/%s.tscn"%track_name])
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
	# Tell client that the race is available.
	_client_receive_race.rpc_id(multiplayer.get_remote_sender_id())
	# Send the ready signal within this server too, in case we're waiting for the host to initialize the race.
	_race_ready.emit()
	# Clean up the car selection menu (now that the race can be displayed).
	# If this was cleaned up too early, then there's be a brief period where nothing is
	# on the screen except a blank grey space.
	await get_tree().create_timer(5.0).timeout
	var selection_menu: CarSelection = get_node('car_selection_'+str(race_id))
	if selection_menu != null:
		selection_menu.queue_free()
@rpc("authority","call_local","reliable")
func _client_receive_race () -> void:
	_race_ready.emit()
signal _race_ready

# This is called to create a multiplayer race among all peers.
# "data" is the race_id, and dictionary containing all players / karts for the race.
func _spawn_race (data: Array) -> Node:
	var race: Node
	var index: int = data[0]
	var race_id: int = data[1]
	var player_ids: Array[int] = data[2]
	var track_scene_path: String = data[3]
	# For the server and participating peers, this will be the fully constructed race.
	var player_id: int = multiplayer.get_unique_id()
	if player_id == 1 or player_id in player_ids:
		race = load("res://world.tscn").instantiate()
		# Each race is offset so that they don't overlap in the coordinate space.
		# So that rigid bodies from different races don't collide with each other... haha.
		race.global_position.x = 100000*index
		var track: Track = load(track_scene_path).instantiate()
		# Set up participants for track (for synchronization of peers).
		# Don't need the specific cars, just the player ids.
		var participants: Dictionary = {}
		for id in player_ids:
			participants[id] = null
		# Need to defer call to this, otehrwise the itemblocks don't show up as children and don't get set up?
		track.call_deferred('setup',participants)
		race.set_track(track)
	# For other peers, just put a simple dummy object here.
	else:
		race = Node.new()
		#race = load("res://world.tscn").instantiate()
		#race.process_mode = Node.PROCESS_MODE_DISABLED
	# Set a consistent name for this race across all peers.
	race.name = "race_"+str(race_id)
	return race


func _on_margin_container_visibility_changed() -> void:
	# When main menu is visible, make Naser car visible and active on the screen.
	if $MarginContainer.visible:
		$NaserCar.process_mode = Node.PROCESS_MODE_INHERIT
		# Defer call to make it work when screen first becomes visible (wait for CarTimer to be scene).
		call_deferred('_reset_and_start_timer')
	# Turn off Naser car when main menu becomes hidden.
	else:
		_reset_car()
		$NaserCar.hide()
		$NaserCar.set_deferred('process_mode',Node.PROCESS_MODE_DISABLED)
