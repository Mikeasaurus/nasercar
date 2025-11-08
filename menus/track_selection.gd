extends Control

@export var tracks: Array[String] = ["default","snowy"]

## The currently selected track.
var selected_track: int

# This internal signal is emitted when the user is done interacting with this menu
# (either when a track is chosen or the user cancels).
signal _done (int)

func run() -> String:
	show()
	var track_index: int = await _done
	#hide()  # Will be hidden later by title screen.
	if track_index >= 0:
		return tracks[track_index]
	else:
		return ""

func _ready() -> void:
	# Add the tracks to the list.
	for track_name in tracks:
		var packed_track: PackedScene = load("res://tracks/%s.tscn"%track_name)
		var entry: TrackEntry = preload("res://menus/track_entry.tscn").instantiate()
		entry.set_track(packed_track)
		$MarginContainer/CenterContainer/VBoxContainer/ScrollContainer/Tracks.add_child(entry)
	# Register click events for selecting a track.
	var t: Array[TrackEntry]
	t.assign($MarginContainer/CenterContainer/VBoxContainer/ScrollContainer/Tracks.get_children())
	for i in range(len(t)):
		var entry: TrackEntry = t[i]
		entry.clicked.connect(func ():
			if i != selected_track:
				t[selected_track].unselect()
				selected_track = i
				t[selected_track].select()
		)
	# Select the first track by default.
	selected_track = 0
	t[selected_track].select()

func _on_back_button_pressed() -> void:
	_done.emit(-1)

func _on_continue_button_pressed() -> void:
	_done.emit(selected_track)
