extends Button

# Handle escape key trigger.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("menu_toggle") and is_visible_in_tree():
		pressed.emit()
		play_back_sound()

func play_back_sound() -> void:
	# Sound effect for back button.
	var sound: AudioStreamPlayer = AudioStreamPlayer.new()
	sound.stream = preload("res://audio/9509__petenice__whoosh.wav")
	sound.volume_db = -10
	sound.finished.connect(sound.queue_free)
	# Put sound in root node so it lasts long enough to finish playing.
	get_tree().root.add_child(sound)
	sound.play()
