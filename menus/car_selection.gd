extends Control

class_name CarSelection

var selection: CarSelectionPanel = null

# The race id.
# Corresponds to the player id who initiated the race.
var race_id: int

# The handle of this player.
var own_handle: String = "Player"

# Current participants for this race.
# Keys are the player ids, values are [handle,car_name].
var participants: Dictionary = {}

# This signal is emitted whenever the list of participants is updated for the race.
# Sent within server instance only.
signal participants_updated (Dictionary)

# Internal signal for when kart selection is done / cancelled.
signal _done (Dictionary)

# This is called by the parent menu to wait for a car to be selected.
# Returns the participants for the race.
func run (handle: String) -> Dictionary:
	own_handle = handle
	show()
	var status: Dictionary = await _done
	# NOTE: Will be freed once race is available, to avoid a brief period of no menus visible while waiting for next screen to be shown.
	return status

# Initialize the menu (from server / local instance).
func setup (new_race_id: int, track: String, locked_cars: Array[String]) -> void:
	self.race_id = new_race_id
	#TODO: get available cars from track info, and set up the panels accordingly.
	for panel: CarSelectionPanel in $MarginContainer/CenterContainer/VBoxContainer/GridContainer.get_children():
		if panel.car.display_name in locked_cars:
			panel.hide()
		else:
			panel.show()

# Helper methods: convert between panel index and car name.
var car_names: Array[String]
func index2name (panel_index: int) -> String:
	if panel_index < 0: return ""
	return car_names[panel_index]
func name2index (carname: String) -> int:
	if carname == "": return -1
	return car_names.find(carname)
func panel2index (panel: CarSelectionPanel) -> int:
	return car_names.find(panel.car.display_name)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	for panel in $MarginContainer/CenterContainer/VBoxContainer/GridContainer.get_children() as Array[CarSelectionPanel]:
		panel.selected.connect(func(): _panel_selected(panel))
		car_names.append(panel.car.display_name)
	# Server side setup.
	if multiplayer.get_unique_id() == 1:
		multiplayer.peer_disconnected.connect(_player_bailed)

func _panel_selected (panel: CarSelectionPanel) -> void:
	var panel_index: int = panel2index(panel)
	# If this is a multiplayer game, then need to delegate car selection through the server.
	if multiplayer.get_unique_id() != 1:
		_try_selecting_car.rpc_id(1,panel_index,own_handle)
		return
	if selection != null and selection != panel:
		selection.unselect()
	selection = panel
	panel.select()
	_update_headshot(panel)
	participants[1] = ["Player", index2name(panel_index)]
	if $MarginContainer/CenterContainer/VBoxContainer/HBoxContainer/RaceButton.disabled:
		$MarginContainer/CenterContainer/VBoxContainer/HBoxContainer/RaceButton.disabled = false

# Helper function - face out the screen.
# Can also be triggered from a server process for multiplayer games.
var _fadeout_time: float = 1.0
@rpc("authority","reliable")
func _fadeout() -> void:
	$StartEngineSound.play()
	var tween: Tween = create_tween()
	tween.tween_property(self,"modulate",Color.BLACK,_fadeout_time)
	await tween.finished

# Called when the user clicks the "Race" button.
func _on_race_button_pressed() -> void:
	# Disable any further button presses.
	$MarginContainer/CenterContainer/VBoxContainer/HBoxContainer/BackButton.disabled = true
	$MarginContainer/CenterContainer/VBoxContainer/HBoxContainer/RaceButton.disabled = true
	# If this is a single player game, send signal back to parent scene that we're ready.
	if multiplayer.get_unique_id() == 1:
		await _fadeout()
		_done.emit(participants)
	# If this is a multiplayer game, delegate to the server for sending the signal to
	# its parent scene.
	else:
		_try_starting_race.rpc_id(1)
# Called from client to server, to request the race to start.
@rpc("any_peer","reliable")
func _try_starting_race() -> void:
	# Remove this from the list of available races, since it has now started.
	participants_updated.emit({})
	# Send some signals to all participating players.
	for p in participants.keys():
		# Fade out their screen as a heads-up that the race is beginning.
		_fadeout.rpc_id(p)
	await get_tree().create_timer(_fadeout_time).timeout
	# Send the list of participants.
	_send_done.rpc(participants)
@rpc("authority","call_local","reliable")
func _send_done (status: Dictionary) -> void:
	_done.emit(status)

# Handle remote updates of kart selections
# This is called on the server when the user clicks on a kart in multiplayer context.
# Based on information I found online, RPC calls are handled in sequence, so no race
# condition can be triggered when multiple peers select the same car at the same time.
# https://forum.godotengine.org/t/rpc-thread-safety-across-peers/112505
@rpc("any_peer","reliable")
func _try_selecting_car (panel_index: int, handle: String) -> void:
	var car_name: String = index2name(panel_index)
	var player_id: int = multiplayer.get_remote_sender_id()
	# Check if the car is already in use.
	for value in participants.values():
		# Each player stores a [handle,car] entry for the race.
		if value[1] == car_name:
			return  # Car already taken
	# Car available, so register this car for the player, and update menu
	# visuals for all peers.
	var old_car_name: String = ""
	if player_id in participants:
		old_car_name = participants[player_id][1]
	participants[player_id] = [handle,car_name]
	participants_updated.emit(participants)
	# Tell other peers that this car is now taken.
	_update_panel.rpc(panel_index,true,player_id,handle)
	# Also, free up previously taken car.
	if old_car_name != "":
		_update_panel.rpc(name2index(old_car_name),false,-1,"")
	# If this player is also the host, then they can join the race whenever they're ready.
	if player_id == race_id:
		_enable_race_button.rpc_id(player_id)
		_info.rpc_id(player_id,"You can wait for others to join, or press \"RACE!\" when you're ready to start.")
	else:
		_info.rpc_id(player_id,"Waiting for the host to start the race.")

# This is called by a new peer to request updated status of the selection panels.
@rpc("any_peer","reliable")
func _sync_panels () -> void:
	var id: int = multiplayer.get_remote_sender_id()
	_info.rpc_id(id,"Please select a kart for the race.")
	# Figure out which race this player is interested in.
	# Start by clearing the status of all cars.
	for car_name in car_names:
		_update_panel.rpc_id(id, name2index(car_name), false, -1, "")
	# For all cars that are already taken, update the panel visual.
	for player_id in participants.keys():
		var value = participants[player_id]
		var handle: String = value[0]
		var car_name: String = value[1]
		if car_name == "": continue
		_update_panel.rpc_id(id, name2index(car_name), true, player_id, handle)

# This is called on the client to update visuals (for when cars are already taken).
@rpc("authority","reliable")
func _update_panel (panel_index: int, is_taken: bool, player_id: int, handle: String) -> void:
	var my_id: int = multiplayer.get_unique_id()
	var panel: CarSelectionPanel = $MarginContainer/CenterContainer/VBoxContainer/GridContainer.get_children()[panel_index]
	# Car is taken by somebody else
	if is_taken and player_id != my_id:
		panel.disable()
		panel.overlay(handle)
	# Car is taken by this player
	elif is_taken and player_id == my_id:
		panel.enable()
		if selection != null and selection != panel:
			selection.unselect()
		selection = panel
		selection.select()
		panel.overlay(handle)
		_update_headshot(panel)
	else:
		panel.unselect()
		panel.enable()
		panel.no_overlay()
# This is called from the server to the client, when they're allowed to click the "Race" button.
@rpc("authority","reliable")
func _enable_race_button () -> void:
	$MarginContainer/CenterContainer/VBoxContainer/HBoxContainer/RaceButton.disabled = false
# This is called to put an informative message on the client's screen.
@rpc("authority","reliable")
func _info (msg: String) -> void:
	$MarginContainer/CenterContainer/VBoxContainer/Info.text = msg
	$MarginContainer/CenterContainer/VBoxContainer/Info.show()


# If joining into a multiplayer game, update the status of all karts.
func _on_visibility_changed() -> void:
	if visible:
		# If this was faded out, then bring it back.
		modulate = Color.WHITE
		# Clear any previously selected car (it's not actually selected anymore).
		if selection != null:
			selection.unselect()
			selection = null
		$Headshot.sprite_frames.clear("default")
		# Enable "Back" button (may have been disabled in previous interaction with this scene).
		$MarginContainer/CenterContainer/VBoxContainer/HBoxContainer/BackButton.disabled = false
		if multiplayer.get_unique_id() != 1:
			# Ask server about which cars are already taken and which ones are available.
			_sync_panels.rpc_id(1)
			# No joining race until a car is selected.
			$MarginContainer/CenterContainer/VBoxContainer/HBoxContainer/RaceButton.disabled = true

# Update the headshot being displayed for the currently selected car.
func _update_headshot (panel: CarSelectionPanel) -> void:
	var car: Car = panel.car
	$Label.text = car.display_name
	var frames: SpriteFrames = $Headshot.sprite_frames
	frames.clear("default")
	for texture: Texture2D in car.headshot:
		frames.add_frame("default",texture)
	$Headshot.play()
	$SelectionSound.play()

# This is called if a player has disconnected from the server.
func _player_bailed (player_id: int) -> void:
	# If this player was hosting the race, then bail on the whole race.
	if player_id == race_id:
		_race_bailed()
		return
	# Otherwise, just clear out the player and free any selected kart.
	if player_id in participants:
		var car_name: String = participants[player_id][1]
		if car_name != "":
			_update_panel.rpc(name2index(car_name),false,-1,"")
		participants.erase(player_id)
		participants_updated.emit(participants)
# This is also from server side.
func _race_bailed () -> void:
	# Kick out all players.
	_send_done.rpc({-1:"The race was cancelled by the host."})
	# Need to clear out participants list, because there's a weird race condition where if
	# other players are joining in, they will send out a signal after the host bails, and will
	# broadcast the list of participants.
	participants.clear()
	participants_updated.emit(participants)

func _on_back_button_pressed() -> void:
	_done.emit({})
