extends HBoxContainer

class_name MultiplayerJoinLine

# This function is called to refresh the list of races.
func update_race (host: String, participants: Array[String], track_name: String) -> void:
	var status: String
	if track_name != "":
		status = "Current race: "+track_name
	else:
		status = "New game starting"
	if host != "":
		status += ", hosted by "+host
	$VBoxContainer/Status.text = status
	var players: String
	if len(participants) > 0:
		players = "Participants: " + ", ".join(participants)
	$VBoxContainer/Players.text = players
