extends Control

@export var tracks: Array[String] = ["default","snowy"]

## The currently selected track.
var selected_track: int

## The peer responsible for track selection.
var manager_id: int = 1

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

func setup(manager: int) -> void:
	manager_id = manager
	var peer_id: int = multiplayer.get_unique_id()
	if peer_id == manager_id:
		$MarginContainer/CenterContainer/VBoxContainer/Title.text = "Choose a track"
		$MarginContainer/CenterContainer/VBoxContainer/HBoxContainer/ContinueButton.disabled = false
	else:
		$MarginContainer/CenterContainer/VBoxContainer/Title.text = "Waiting for host to choose a track"
		$MarginContainer/CenterContainer/VBoxContainer/HBoxContainer/ContinueButton.disabled = true

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

func _on_continue_button_pressed() -> void:
	_submit_race.rpc_id(1)

@rpc("any_peer","call_local","reliable")
func _submit_race () -> void:
	if multiplayer.get_remote_sender_id() == manager_id:
		# Tell all players that track selection is done.
		_broadcast_track.rpc(selected_track)

@rpc("authority","call_local","reliable")
func _broadcast_track (i: int) -> void:
	_done.emit(i)
