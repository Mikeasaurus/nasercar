extends Control

func _on_button_pressed() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WindowMode.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WindowMode.WINDOW_MODE_WINDOWED)
		# Fix a bug where it doesn't actually go to windowed mode the first time
		# you click from full screen.  This mimicks clicking it a second time (which works???)
		await get_tree().create_timer(0.1).timeout
		DisplayServer.window_set_mode(DisplayServer.WindowMode.WINDOW_MODE_WINDOWED)
