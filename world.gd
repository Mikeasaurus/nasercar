extends Node2D
class_name World

# Internal signal that gets emitted when the game is finished and the player wishes to exit.
signal _done (place: int)

# List of particpants for the race.
# Filled in by the parent scene.
var participants: Dictionary

# Current game state (for applied effects, etc.)

# Time of start of race.
var _start_time: float

# Indicates that people are already slimed right now, or at least that someone
# has possession of the slime item.
var _sliming: bool = false
# Indicates that someone already has possession of the meteor.
var _meteor: bool = false

# Keep track of player's place in the race.
var _place: Dictionary
# Shortcut for updating results for the stats page.
var _final_stats: Array[ResultLine] = []
var _finished_cars: Array[Car] = []

# Keep track of which cars are carrying which items.
var _current_items: Dictionary = {}

# Shortcut to the track for this race.
var track: Track

# Helper method - get all cars in this track.
# Omits other non-car entities that the cars may spawn as siblings.
# Cache this value for future reference.
var _cars_cache: Array[Car] = []
func _cars () -> Array[Car]:
	if len(_cars_cache) == 0:
		for car in track.get_node('StartingPositions').get_children():
			if "CarType" in car:
				_cars_cache.append(car)
	return _cars_cache
# Helper method - get all cars in front of the specified car.
func _cars_in_front_of (car: Car) -> Array[Car]:
	var cars: Array[Car] = []
	for other_car in _cars():
		if other_car.progress() > car.progress():
			cars.append(other_car)
	return cars
# Helper method - get place of the specified car.
func _car_place (car: Car) -> int:
	return len(_cars_in_front_of(car)) + 1
# Helper method - get the car immediately in front of the specified car.
# Returns null if there are no cars in front.
func _car_in_front_of (car: Car) -> Car:
	var front: Car = null
	var front_progress: float = -1
	for other_car in _cars_in_front_of(car):
		if other_car.progress() < front_progress or front_progress < 0:
			front = other_car
			front_progress = other_car.progress()
	return front
# Helper method - get the car in first place.
func _first_place_car () -> Car:
	var progress: float = 0.0
	var car: Car
	for c in _cars():
		if c.progress() > progress:
			car = c
			progress = c.progress()
	return car
# Helper method - get number of cars behind the specified car.
func _num_cars_behind (car: Car) -> int:
	var num: int = 0
	for other_car in _cars():
		if other_car.progress() < car.progress():
			num += 1
	return num

# Helper method (for server-side): find the player associated with the given car.
# Returns 0 if no player associated with it.
func _get_player_id (car: Car) -> int:
	for player_id in participants.keys():
		if participants[player_id] == car:
			return player_id
	return 0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Prepare final stats screen with placeholder values.
	var result_scene: PackedScene = load("res://menus/result_line.tscn")
	var places_vbox: VBoxContainer = $CanvasLayer/Stats/CenterContainer/Places
	# Set up blank entries for results (to be filled in)
	for i in range(8):
		var result_line: ResultLine = result_scene.instantiate()
		result_line.name = "result"+str(i)  # Consistent name to help with RPC calls into this object.
		result_line.set_results(-1, "", "", -1, Color.hex(0x555555ff))
		places_vbox.add_child(result_line)
		_final_stats.append(result_line)
		var hsep: HSeparator = HSeparator.new()
		hsep.add_theme_constant_override("separation",5)
		var stylebox: StyleBoxLine = StyleBoxLine.new()
		stylebox.color = Color.hex(0x777777ff)
		stylebox.thickness = 3
		hsep.add_theme_stylebox_override("separator", stylebox)
		places_vbox.add_child(hsep)

# Call this during race creation.
func set_track (new_track: Track) -> void:
	# Store a reference to the track, and place it in the visible area.
	self.track = new_track
	add_child(new_track)
	# Set up map overlay.
	$MapOverlay.set_track(new_track)

# Called to do final setup of race, and start it.
func run (participants_in: Dictionary) -> int:
	# Now that we know the participants, can find out which car is the current player's car.
	# Move the map icon for that car to the front of visibility.
	var id: int = multiplayer.get_unique_id()
	if id in participants_in:
		var carname: String = participants_in[id][1]
		for c in _cars():
			if c.display_name == carname:
				$MapOverlay.move_to_front(c)
	# If this is the host, then start the race.
	if multiplayer.get_unique_id() == 1:
		_start_race(participants_in)
	# Wait until race is finished, and return the final place.
	# Place will be -1 for unfinished race?
	var place: int = await _done
	return place

# Starts the race (countdown, then activate cars).
func _start_race (participants_in: Dictionary) -> void:

	if multiplayer.get_unique_id() != 1:
		print ("Attempted to call World.run on a passive peer.")
		return

	# Hook up server signals.
	if multiplayer.get_unique_id() == 1:
		multiplayer.multiplayer_peer.peer_disconnected.connect(_player_disconnected)

	# Match each player to their car scene in the race.
	# participants variable gets updated from [player_name,car_name] to instances of car objects.
	var cars: Array[Car] = _cars()
	self.participants = {}
	for player_id in participants_in.keys():
		for car in cars:
			var player_name: String = participants_in[player_id][0]
			var car_name: String = participants_in[player_id][1]
			if car.display_name == car_name:
				self.participants[player_id] = car
				# Update the names of player car(s)
				# Use the handle for multiplayer, or (Player) for single player.
				if 1 in participants_in:
					car.display_name = car.display_name + " (Player)"
				else:
					car.display_name = player_name
					car.show_nameplate(player_name)

	# Move the playable car(s) to the front.
	var positions: Array[Vector2] = []
	for c in _cars():
		positions.append(c.global_position)
	var car_order: Array[Car] = []
	for c in self.participants.values():
		car_order.append(c)
	for c in _cars():
		if c not in car_order:
			car_order.append(c)
	for i in range(len(car_order)):
		var c: Car = car_order[i]
		var p: Vector2 = positions[i]
		c.global_position = p

	# Add the cars to the track.
	# (Let the cars know what path to follow, and whether they are CPU or player controlled).
	var trackpath: Path2D = track.get_node("TrackPath")
	var tiles: Array[TileMapLayer]
	tiles.assign(track.get_node("TilesBelowCars").get_children())
	for car in cars:
		car.add_to_track(trackpath, tiles)
		car.itemblock.connect(func():
			_itemblock(car)
		)
		car.meteor_impact.connect(func():
			_big_badaboom(car)
		)
		car.lap_completed.connect(func(lap:int):
			_lap_completed(car,lap)
		)

	# For single-player game, set up a car under the player's control, and local CPUs.
	if 1 in self.participants:
		self.participants[1].make_local_playable()
		for car in cars:
			if car not in self.participants.values():
				car.make_local_cpu()
				car.display_name = car.display_name + " (CPU)"

	# For multiplayer game, set local controls but remote management for players, and
	# remotely managed CPUs
	else:
		for player_id in self.participants.keys():
			var car: Car = self.participants[player_id]
			for id in self.participants.keys():
				if id == player_id:
					car.make_remote_playable_clientside.rpc_id(id)
				else:
					car.make_remote.rpc_id(id)
			car.make_remote_playable_serverside()
		for car in _cars():
			# All non-player cars are treated as CPU-controlled on server, and
			# remotely managed on clients.
			if car not in self.participants.values():
				car.make_local_cpu()
				car.display_name = car.display_name + " (CPU)"
				car.make_remote.rpc()

	# Set default values of car places, to be computed in _process.
	for player_id in self.participants:
		_place[player_id] = 0

	# Start of race.
	$CanvasLayer/FadeIn.show()
	$CanvasLayer/Place.modulate = Color.hex(0xffffff00)
	var fadein: Tween = create_tween()
	fadein.tween_property($CanvasLayer/FadeIn, "modulate", Color.TRANSPARENT, 1.0)
	await fadein.finished
	$CanvasLayer/GoLabel.show()
	$CanvasLayer/GoLabel.text = "3"
	$Beep1.play()
	await get_tree().create_timer(1.0, false).timeout
	$CanvasLayer/GoLabel.text = "2"
	$Beep1.play()
	await get_tree().create_timer(1.0, false).timeout
	$CanvasLayer/GoLabel.text = "1"
	$Beep1.play()
	await get_tree().create_timer(1.0, false).timeout
	$CanvasLayer/GoLabel.text = "GO!!!"
	$Beep2.play()
	for car in _cars():
		car.go()
	_start_time = Time.get_ticks_msec() / 1000.
	var go: Tween = create_tween()
	go.tween_property($CanvasLayer/GoLabel,"modulate",Color.TRANSPARENT,1.0)
	go.parallel().tween_property($CanvasLayer/GoLabel,"scale",Vector2(2,2),1.0)
	go.parallel().tween_property($CanvasLayer/GoLabel,"position", Vector2($CanvasLayer/GoLabel.position.x*0.5,1),1.0)
	# Show place after the cars have starting racing a bit.
	await get_tree().create_timer(3.0, false).timeout
	var place_tween: Tween = create_tween()
	place_tween.set_ease(Tween.EASE_IN)
	place_tween.tween_property($CanvasLayer/Place, "modulate", Color.WHITE, 1.0)
	await place_tween.finished


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	# Update the places of all the cars.
	# Determined on the server side.
	if multiplayer.get_unique_id() == 1:
		#TODO: more efficient code - this requires a loop inside _car_place.
		for player_id in _place.keys():
			if player_id not in participants: continue  # In case player already left the race.
			var car: Car = participants[player_id]
			# Don't update the place of cars that already crossed the finish line.
			if car in _finished_cars: continue
			var old_place: int = _place[player_id]
			var new_place: int = _car_place(participants[player_id])
			if old_place != new_place:
				_place[player_id] = new_place
				_update_displayed_place.rpc_id(player_id, new_place)
@rpc("authority","reliable","call_local")
func _update_displayed_place (place: int) -> void:
	var dt: float = 0.5
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property($CanvasLayer/Place, "scroll_vertical", (place-1)*175, dt)
	await tween.finished

# All available item types.
enum ItemType {NONE,NAILPOLISH,COFFEE,METEOR,SLIME,BEETLE}
# Map the item types to the visual representations.
@onready var item_pics: Dictionary = {
	ItemType.NAILPOLISH: $ItemSelect/CenterContainer/ScrollContainer/VBoxContainer/NailPolish,
	ItemType.COFFEE: $ItemSelect/CenterContainer/ScrollContainer/VBoxContainer/Coffee,
	ItemType.METEOR: $ItemSelect/CenterContainer/ScrollContainer/VBoxContainer/Meteor,
	ItemType.SLIME: $ItemSelect/CenterContainer/ScrollContainer/VBoxContainer/MangoSlime,
	ItemType.BEETLE: $ItemSelect/CenterContainer/ScrollContainer/VBoxContainer/Beetle,
}

# Item block touched by car.
# Called from within server / single-player side.
func _itemblock (car: Car) -> void:
	if car not in _current_items:
		_get_item(car)

var _paused: bool = false
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("menu_toggle"):
		# Check if already paused (or in process of unpausing).
		if _paused: return
		_paused = true
		# Only truly pause for single-player games.
		if multiplayer.get_unique_id() == 1:
			get_tree().paused = true
		var quit: bool = await $ScreenEffects/PauseMenu.run()
		if quit:
			_leave_race(false)
		else:
			get_tree().paused = false
			set_deferred('_paused',false)
	# Client side input capture for using an item.
	if event.is_action_pressed("use_item"):
		_use_item.rpc_id(1)

func _get_item(car: Car) -> void:
	# First, select an item.
	# Put stub entry for this car, to prevent getting another item while this
	# item is arriving.
	_current_items[car] = ItemType.NONE
	var cars_in_front: Array[Car] = _cars_in_front_of(car)
	# Determine which items are viable selections, and relative probability
	# of occurrence.
	var likelihood: Dictionary = {}
	# Probability of slime increases with number of cars in front.
	# But not available if someone else already has it / is using it.
	if not _sliming:
		if len(cars_in_front) > 0:
			likelihood[ItemType.SLIME] = len(cars_in_front)*5
	# Coffee also becomes more likely the further behind.
	if len(cars_in_front) >= 0:  # This condition can be used to turn off coffee if already in front.
		likelihood[ItemType.COFFEE] = 10 + len(cars_in_front)*15
	# Similarly, probability of meteor increases with number of cars in front.
	# But relatively less likely overall.
	if not _meteor:
		if len(cars_in_front) > 0:
			likelihood[ItemType.METEOR] = len(cars_in_front)
	# Probability of nail polish increases with number of cars behind.
	var num_cars_behind: int = _num_cars_behind(car)
	if num_cars_behind > 0:
		likelihood[ItemType.NAILPOLISH] = num_cars_behind*10
	# Beetle has equal probability, except for leading car.
	if len(cars_in_front) > 0:
		likelihood[ItemType.BEETLE] = 40
	# Pick an item from these possibilities.
	var sample_size: int = 0
	for n in likelihood.values():
		sample_size += n
	var choice: int = randi() % sample_size
	#print ('?? ', car, ' ', likelihood, ' ', sample_size)
	var item: ItemType
	for item_type in likelihood.keys():
		if choice < likelihood[item_type]:
			item = item_type
			break
		choice -= likelihood[item_type]
	# An item should now be selected.
	#print (car, ' got ', item_pics[item])

	# Some item types are exclusive (only one available at a time).
	if item == ItemType.METEOR:
		_meteor = true
	if item == ItemType.SLIME:
		_sliming = true

	# If this is player, then spin to this item.
	# Send rpc to the client to update visual for item selection.
	if car.type == car.CarType.PLAYER:
		_item_selection_visual.rpc_id(_get_player_id(car), item)
	else:
		await get_tree().create_timer(2.0, false).timeout
	_current_items[car] = item
	# CPUs use items automatically after some random amount of time.
	if car.type == car.CarType.CPU:
		await get_tree().create_timer(randf()*5, false).timeout
		_use_item(car)

# Called from server to client, to update visual for item selection.
@rpc("authority","reliable","call_local")
func _item_selection_visual (item: ItemType) -> void:
	# Move item picture to the last entry.
	$ItemSelect/CenterContainer/ScrollContainer/VBoxContainer.move_child(item_pics[item],-1)
	$ItemSelect.show()
	$ItemSelect/CenterContainer/ScrollContainer.scroll_vertical = 0
	$ItemSelect/D20Sound.play()
	var tween: Tween = create_tween()
	tween.tween_interval(0.4)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property($ItemSelect/CenterContainer/ScrollContainer,"scroll_vertical",5*256+20,0.75)
	await tween.finished
	# Players with touchscreen automatically use items after a short amount of time.
	if DisplayServer.is_touchscreen_available():
		await get_tree().create_timer(1.0, false).timeout
		_use_item.rpc_id(1)

# Called from client to server, to indicate the item should be used.
@rpc("any_peer","reliable","call_local")
func _use_item(car: Car = null) -> void:
	# If no car specified, then find car based on which client made this rpc call.
	if car == null:
		var player_id: int = multiplayer.get_remote_sender_id()
		car = participants[player_id]
	# Check if there's actually any item for this car to use.
	if car not in _current_items: return
	#print (car, ' used ', item_pics[_current_items[car]])
	var item: ItemType = _current_items.get(car)
	if item == ItemType.NONE: return  # Item not available yet.
	_current_items.erase(car)
	if car.type == car.CarType.PLAYER:
		_item_usage_visual.rpc_id(_get_player_id(car),item)
	if item == ItemType.SLIME:
		for c in _cars_in_front_of(car):
			c.get_slimed(0.7+0.4, 4.0, 2.0)
			if c.type == c.CarType.PLAYER:
				_slime_screen.rpc_id(_get_player_id(c))
		# Allow slime item to be obtained again after slime has faded.
		await get_tree().create_timer(7.1, false).timeout
		_sliming = false
	if item == ItemType.BEETLE:
		# Target the car in front.
		var target: Car = _car_in_front_of(car)
		_launch_beetle(car, target)
	if item == ItemType.NAILPOLISH:
		_release_nailpolish(car)
	if item == ItemType.COFFEE:
		car.sip_coffee()
	if item == ItemType.METEOR:
		_launch_meteor(car)
# Called from server to client, to trigger visual feedback of using the item.
@rpc("authority","reliable","call_local")
func _item_usage_visual (item: ItemType) -> void:
	# Play item activation sound.
	# Skipped for certain items which have their own distinct sound.
	if item not in [ItemType.NAILPOLISH, ItemType.COFFEE]:
		$ItemSelect/WhooshSound.play()
	var tween: Tween = create_tween()
	tween.tween_property($ItemSelect/CenterContainer,"scale",Vector2(1.0,1.0),0.2)
	tween.parallel().tween_property($ItemSelect/CenterContainer,"modulate",Color.hex(0xffffff00),0.2)
	await tween.finished
	$ItemSelect.hide()
	$ItemSelect/CenterContainer.scale = Vector2(0.5,0.5)
	$ItemSelect/CenterContainer.modulate = Color.WHITE

@rpc("authority","reliable","call_local")
func _slime_screen() -> void:
	$ScreenEffects/MangoSlime.show()
	var mango: AnimatedSprite2D = $ScreenEffects/MangoSlime/Mango
	mango.offset.y = 0
	mango.scale.y = 9
	var mangotween: Tween = create_tween()
	mangotween.set_ease(Tween.EASE_IN)
	mangotween.tween_property(mango, "offset", Vector2(0,-108), 0.5)
	mangotween.tween_interval(0.2)
	#tween.tween_property(mango, "scale", Vector2(9,10), 0.0)
	mangotween.tween_interval(0.4)
	#tween.tween_property(mango, "scale", Vector2(9,9), 0.0)
	mangotween.tween_interval(0.2)
	mangotween.set_ease(Tween.EASE_OUT)
	mangotween.tween_property(mango, "offset", Vector2(0,0), 0.3)
	await get_tree().create_timer(0.7, false).timeout
	mango.animation = "mouth_open"
	$ScreenEffects/MangoSlime/CPUParticles2D.emitting = true
	$ScreenEffects/MangoSlime/HorkSound.play()
	await get_tree().create_timer(0.4, false).timeout
	$ScreenEffects/MangoSlime/SplatSound.play()
	var slime: AnimatedSprite2D = $ScreenEffects/MangoSlime/Slime
	slime.show()
	slime.play()
	mango.animation = "default"
	#await mangotween.finished
	#slime.hide()
	var slimedrip: Tween = create_tween()
	slimedrip.set_ease(Tween.EASE_OUT)
	var slimefade: Tween = create_tween()
	slimefade.set_ease(Tween.EASE_OUT)
	slimedrip.tween_property(slime, "scale", Vector2(10,50), 6.0)
	slimefade.tween_interval(4.0)
	slimefade.tween_property(slime, "modulate", Color.hex(0xffffff00), 2.0)
	await slimefade.finished
	if slimedrip.is_running():
		await slimedrip.finished
	slime.hide()
	slime.scale.y = 10
	slime.modulate = Color.WHITE
	$ScreenEffects/MangoSlime.hide()

func _launch_beetle (from: Car, to: Car) -> void:
	var beetle = load("res://items/beetle.tscn").instantiate()
	add_child(beetle,true)
	beetle.z_index = 10
	beetle.global_position = from.global_position
	beetle.velocity = from.linear_velocity
	if to != null:
		beetle.set_target(to)
	else:
		beetle.buzz_off()

func _launch_meteor (from: Car) -> void:
	var target: Car = _first_place_car()
	# If player managed to get into first place, then don't launch the meteor at
	# themselves!
	if target == from: return
	target.space_rock()

func _release_nailpolish (from: Car) -> void:
	var nailpolish = load("res://items/nail_polish.tscn").instantiate()
	add_child(nailpolish,true)
	nailpolish.global_position = from.global_position
	nailpolish.z_index = 0  # Under item blocks and things.

func _big_badaboom (car: Car) -> void:
	# Flash of light
	var boom: Node2D = load("res://effects/impact.tscn").instantiate()
	add_child(boom,true)
	boom.global_position = car.global_position
	boom.z_index = 3
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(boom,"scale",Vector2(3,3),0.5)
	tween.tween_interval(1.0)
	tween.tween_property(boom,"modulate",Color.hex(0xffffff00),5.0)
	tween.parallel().tween_property(boom,"scale",Vector2(9,9),5.0)
	# Smoulder effect (and impedence) on all cars within the blast radius.
	for c in _cars():
		if "smoulder" in c and (c.global_position-boom.global_position).length() <= 500:
			c.smoulder()
	# Smoking crater.
	var crater: Node2D = load("res://effects/crater.tscn").instantiate()
	add_child(crater,true)
	crater.global_position = car.global_position
	crater.z_index = 2
	crater.get_node("CPUParticles2D").emitting = true
	await tween.finished
	_meteor = false
	boom.queue_free()
	await get_tree().create_timer(10.0, false).timeout
	crater.queue_free()

# Called when a car has just completed a lap.
func _lap_completed (car: Car, lap: int) -> void:
	if lap < track.laps:
		if car.type == car.CarType.PLAYER:
			_lap_announce.rpc_id(_get_player_id(car), lap+1)
	elif lap == track.laps:
		_finished(car)
# Announce the player's new lap on the screen.
@rpc("authority","reliable","call_local")
func _lap_announce (lap: int):
	var t: Label = $CanvasLayer/LapFinished
	if lap < track.laps:
		t.text = "Lap %d"%lap
	else:
		t.text = "Final Lap"
	t.global_position = Vector2(-t.size.x*t.scale.x,0)
	t.show()
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(t,"global_position", Vector2(960-t.size.x*t.scale.x/2,0),0.5)
	tween.tween_interval(0.5)
	tween.tween_property(t,"global_position", Vector2(1920,0),0.5)
	await tween.finished
	t.hide()
# End of the race (player crossed finish line).
func _finished (car: Car) -> void:
	# Add this car to the displayed stats.
	var time: float = Time.get_ticks_msec()/1000. - _start_time
	# First append this car to an array, then apply all the array elements to
	# the stats page.
	# This avoids a race condition when two cars finish at the same time and are both trying to
	# update their stats.
	_finished_cars.append(car)
	for i in range(len(_finished_cars)):
		if _finished_cars[i] == car:
			var place: int = i+1
			for player_id in participants.keys():
				var text_colour: Color = Color.WHITE
				# Highlight the player's name in green on their own screen.
				if participants[player_id] == car:
					text_colour = Color.GREEN
				_final_stats[i].set_results.rpc_id(player_id, place, car.scene_file_path, car.display_name, time, text_colour)
	if car.type == car.CarType.PLAYER:
		# Immediately use any item that is still held by the player.
		_use_item(car)
		# CPU takes control of car after race, so cars are still moving in the background
		# while the player reads the final results.
		car.autopilot()
		# Rest of this is for the player's screen.
		_finished_announce.rpc_id(_get_player_id(car))
@rpc("authority","reliable","call_local")
func _finished_announce() -> void:
	$CanvasLayer/Place.hide()
	$CanvasLayer/FinishSound.play()
	var t: Label = $CanvasLayer/LapFinished
	t.text = "FINISHED"
	t.global_position = Vector2(-t.size.x*t.scale.x,0)
	t.show()
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(t,"global_position", Vector2(960-t.size.x*t.scale.x/2,0),0.5)
	tween.tween_interval(0.5)
	$CanvasLayer/Stats.modulate = Color.hex(0xffffff00)
	$CanvasLayer/Stats.show()
	tween.tween_property($CanvasLayer/Stats,"modulate",Color.WHITE,0.5)
	$CanvasLayer/DoneButton.modulate = Color.hex(0xffffff00)
	$CanvasLayer/DoneButton.show()
	$CanvasLayer/DoneButton.disabled = true
	tween.parallel().tween_property($CanvasLayer/DoneButton,"modulate",Color.WHITE,0.5)
	await tween.finished
	$CanvasLayer/DoneButton.disabled = false

func _on_done_button_pressed() -> void:
	$CanvasLayer/DoneButton.disabled = true
	_leave_race(true)
var _leaving_race: bool = false
func _leave_race(completed: bool = false) -> void:
	# Check if already leaving race.
	if _leaving_race: return
	_leaving_race = true
	var tween: Tween = create_tween()
	# Allow this fadeout tween to run even though the scene is probably paused right now.
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(self,"modulate",Color.BLACK,1.0)
	# Why do I need to modulate stats if I'm already modulating the whole scene???
	# I think it's because they're in their own CanvasLayer, so don't get affected by parent modulation?
	tween.parallel().tween_property($CanvasLayer/Stats,"modulate",Color.BLACK,1.0)
	tween.parallel().tween_property($CanvasLayer/LapFinished,"modulate",Color.BLACK,1.0)
	for c in $MapOverlay.get_children():
		tween.parallel().tween_property(c,"modulate",Color.BLACK,1.0)
	await tween.finished
	# Unpause the tree so the main menu and other elements will function properly once we leave the race.
	get_tree().paused = false
	_leaving_race = false
	# For completed single-player games, return the player's place.
	var my_id: int = multiplayer.get_unique_id()
	if completed and my_id == 1:
		_done.emit(_place[my_id])
	# For incomplete single-player games, don't have a place to return.
	elif not completed and my_id == 1:
		_done.emit(-1)
	# For multiplayer games, just return without the place.
	# (the place is stored in the server context, not available here).
	# It could be communicated, if needed for some reason.
	elif my_id != 1:
		_done.emit(-1)
	# For single player games, clean up the race.
	# Multiplayer games get cleaned up after all players disconnected from server (see below).
	if my_id == 1:
		queue_free()

# Handle peer disconnections.
# Clean up the race after all players have left.
func _player_disconnected (player_id: int) -> void:
	var car: Car = self.participants[player_id]
	car.hide_nameplate()
	car.autopilot()
	self.participants.erase(player_id)
	if len(self.participants) == 0:
		queue_free()
