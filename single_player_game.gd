extends "res://game.gd"

# Called at conclusion of race
func _race_ended (track_name: String, place: int) -> void:
	# Check if a character was unlocked.
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer and place == 1 and "Naomi" in locked_cars:
		await $Naomi.run()
		locked_cars.erase("Naomi")
