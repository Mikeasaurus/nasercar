extends Control

@onready var _handle: LineEdit = $MarginContainer/CenterContainer/VBoxContainer/HBoxContainer2/Handle

# Keep track of all the races currently being set up.
var available_races: Dictionary = {}

# Internal signal sent when the user is finished interacting with this menu.
signal _done (race_id: int, handle: String)

func run() -> Array:
	show()
	var info: Array = await _done
	#hide()  # Will be re-hidden from context of main menu, to avoid a brief period of no menus visible while waiting for next menu to be shown.
	return info

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$RaceEntrySpawner.spawn_function = _spawn_race_entry

func _on_back_button_pressed() -> void:
	_done.emit(-1,"")

# Player wants to start their own multiplayer session.
func _on_new_button_pressed() -> void:
	if len(_handle.text) == 0:
		$NameWarning.show()
		return
	$NameWarning.hide()
	_done.emit(multiplayer.get_unique_id(),_handle.text)

# This function is called to refresh the list of races.
func update_race (race_id: int, track_name: String, participants: Dictionary) -> void:
	# If this is a new race, then add it to the list.
	if race_id not in available_races:
		available_races[race_id] = $RaceEntrySpawner.spawn(race_id)
		var handle: String = "Someone"
		# Get race host.
		if race_id in participants: handle = participants[race_id][0]
		available_races[race_id].get_node("VBoxContainer/Host").text = "%s is starting a new race"%handle
	var entry: Node = available_races[race_id]
	# Update number of participants.
	entry.get_node("VBoxContainer/NumPlayers").text = "Track: \"%s\"   %d player(s) joined so far"%[track_name, len(participants)]
	# If an empty list of participants was given, then the race is not available to join anymore.
	if len(participants) == 0:
		available_races.erase(race_id)
		entry.queue_free()
	# If no races available, then show a message.
	if len(available_races) == 0:
		$MarginContainer/CenterContainer/VBoxContainer/ScrollContainer/VBoxContainer/NoRacesLabel.show()
	else:
		$MarginContainer/CenterContainer/VBoxContainer/ScrollContainer/VBoxContainer/NoRacesLabel.hide()

# Called when a new line is added to the list of available races.
# Where is race id going to be stored?
func _spawn_race_entry (id: int):
	var entry = load("res://menus/multiplayer_join_line.tscn").instantiate()
	entry.get_node("JoinButton").pressed.connect(func ():
		if len(_handle.text) == 0:
			$NameWarning.show()
			return
		$NameWarning.hide()
		_done.emit(id,_handle.text)
	)
	entry.name = str(id)
	return entry
