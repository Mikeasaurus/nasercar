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
