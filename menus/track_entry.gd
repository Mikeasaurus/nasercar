extends Panel

class_name TrackEntry

# Signal that is sent when this track entry is clicked on.
signal clicked

func set_track (packed_track: PackedScene) -> void:
	var track: Track = packed_track.instantiate()
	$HBoxContainer/Thumbnail.texture = track.thumbnail_image
	$HBoxContainer/VBoxContainer/Name.text = track.name
	$HBoxContainer/VBoxContainer/Description.text = track.description

func select () -> void:
	$Highlight.show()

func unselect () -> void:
	$Highlight.hide()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		clicked.emit()
