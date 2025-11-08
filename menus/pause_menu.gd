extends Control

signal _done (quit:bool)

func _ready() -> void:
	# For multiplayer games, change the pause menu a bit (not actually paused,
	# and not "quitting" the game, just leaving it.
	if multiplayer.get_unique_id() != 1:
		$MarginContainer/CenterContainer/VBoxContainer/Label.hide()
		$MarginContainer/CenterContainer/VBoxContainer/QuitButton.text = "Leave Race"

func run () -> bool:
	show()
	var quit: bool = await _done
	# If unpausing (and continuing game), hide the pause menu.
	if not quit:
		hide()
	# Otherwise, hide the elements but keep the fade-out.
	else:
		$MarginContainer/CenterContainer/VBoxContainer.hide()
	return quit

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("menu_toggle"):
		_done.emit(false)

func _on_quit_button_pressed() -> void:
	_done.emit(true)
