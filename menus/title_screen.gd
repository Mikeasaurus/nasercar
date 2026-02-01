extends Control

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var notracks: Array[TileMapLayer] = []
	$NaserCar.add_to_track($Path2D,notracks)
	$NaserCar.make_local_cpu()
	_reset_and_start_timer()
	# Turn off the Naser car for server instance, otherwise it gets synchronized to all the players and
	# they see an extra car floating around the screen!
	if DisplayServer.get_name() == "headless":
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

"""
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
	#TODO
	#selection_menu = await _request_car_selection_menu (race_id, track_name)
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
	# If a race wasn't run (e.g. user cancelled at car selection), then need to free
	# the car selection menu here.  It won't be cleaned up by the _request_race logic in this case.
	else:
		selection_menu.queue_free()
	# Show the main menu again.
	$MarginContainer.show()
"""

func _on_single_player_pressed() -> void:
	$MarginContainer.hide()
	await $SinglePlayer.run("Player")
	$MarginContainer.show()

# When multiplayer is clicked, need to start a connection to the server.
func _on_multiplayer_pressed() -> void:
	$MarginContainer.hide()
	await $Multiplayer.run()
	$MarginContainer.show()

func _on_car_timer_timeout() -> void:
	$NaserCar.freeze = false
	$NaserCar.go()


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
