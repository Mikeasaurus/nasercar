extends Control

@export var tracks: Array[String] = ["default","snowy"]

## The currently selected track.
var selected_track: int

## The peer responsible for track selection.
@export var manager_id: int = 1

# Current game participants for multiplayer server.
# (reference)
var participants: Dictionary

# This internal signal is emitted when the user is done interacting with this menu
# (either when a track is chosen or the user cancels).
signal _done (int)

func run() -> String:
	show()
	var track_index: int = await _done
	hide()
	if track_index >= 0:
		return tracks[track_index]
	else:
		return ""

func setup(manager: int, participants_: Dictionary) -> void:
	manager_id = manager
	participants = participants_

func _ready() -> void:
	# Add the tracks to the list.
	for track_name in tracks:
		var packed_track: PackedScene = load("res://tracks/%s.tscn"%track_name)
		var entry: TrackEntry = preload("res://menus/track_entry.tscn").instantiate()
		entry.set_track(packed_track)
		entry.name = track_name
		$MarginContainer/CenterContainer/VBoxContainer/ScrollContainer/Tracks.add_child(entry)
	# Register click events for selecting a track.
	var t: Array[TrackEntry]
	t.assign($MarginContainer/CenterContainer/VBoxContainer/ScrollContainer/Tracks.get_children())
	for i in range(len(t)):
		var entry: TrackEntry = t[i]
		entry.clicked.connect(func ():
			_select.rpc_id(1,i)
		)
	# Select the first track by default.
	if multiplayer.get_unique_id() == 1:
		selected_track = 0
		t[selected_track].select()

# Register click events for selecting a track.
@rpc("any_peer","call_local","reliable")
func _select (i: int) -> void:
	if multiplayer.get_remote_sender_id() != manager_id: return
	var t: Array[TrackEntry]
	t.assign($MarginContainer/CenterContainer/VBoxContainer/ScrollContainer/Tracks.get_children())
	if i != selected_track:
		t[selected_track].unselect()
		selected_track = i
		t[selected_track].select()

func _on_back_button_pressed() -> void:
	_done.emit(-1)

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
	var peer_id: int = multiplayer.get_unique_id()
	if peer_id == 1:
		await _fadeout()
		_done.emit(selected_track)
	# If this is a multiplayer game, delegate to the server for sending the signal to
	# its parent scene.
	# (can only be done by manager of the race).
	elif peer_id == manager_id:
		_try_starting_race.rpc_id(1)
# Called from client to server, to request the race to start.
@rpc("any_peer","reliable")
func _try_starting_race() -> void:
	var peer_id: int = multiplayer.get_remote_sender_id()
	if peer_id != manager_id: return  # Only race manager can start the race.
	# Send some signals to all participating players.
	for p in participants.keys():
		# Fade out their screen as a heads-up that the race is beginning.
		_fadeout.rpc_id(p)
	await get_tree().create_timer(_fadeout_time).timeout
	_send_done.rpc(selected_track)
@rpc("authority","call_local","reliable")
func _send_done (track: int) -> void:
	_done.emit(track)

func _on_visibility_changed() -> void:
	if visible:
		# If this was faded out, then bring it back.
		modulate = Color.WHITE
		# Enable "Back" button (may have been disabled in previous interaction with this scene).
		$MarginContainer/CenterContainer/VBoxContainer/HBoxContainer/BackButton.disabled = false
		# Could start next race with previously selected track (at least for single player game).
		if multiplayer.multiplayer_peer is OfflineMultiplayerPeer or multiplayer.get_unique_id() == manager_id:
			$MarginContainer/CenterContainer/VBoxContainer/HBoxContainer/RaceButton.disabled = false
		else:
			$MarginContainer/CenterContainer/VBoxContainer/HBoxContainer/RaceButton.disabled = true
		var peer_id: int = multiplayer.get_unique_id()
		if peer_id == manager_id:
			$MarginContainer/CenterContainer/VBoxContainer/Title.text = "Choose a track"
			$MarginContainer/CenterContainer/VBoxContainer/HBoxContainer/RaceButton.disabled = false
		else:
			$MarginContainer/CenterContainer/VBoxContainer/Title.text = "Waiting for host to choose a track"
			$MarginContainer/CenterContainer/VBoxContainer/HBoxContainer/RaceButton.disabled = true
