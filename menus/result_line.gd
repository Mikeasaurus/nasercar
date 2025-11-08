extends HBoxContainer

class_name ResultLine

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.
	#set_results(2, load("res://cars/naser_car.tscn").instantiate(), "Naser (CPU)", 64.0, Color.GREEN)

@rpc("authority","reliable","call_local")
func set_results (place: int, car_path: String, racer_name: String, time: float, colour: Color = Color.WHITE) -> void:
	if place > 0:
		$Place.text = str(place)
	$Place.modulate = colour
	if car_path != '':
		var car: Car = load(car_path).instantiate()
		$Car/SubViewport.add_child(car)
		car.scale = Vector2(0.5,0.5)
		car.position = Vector2(40,40)
		car.process_mode = Node.PROCESS_MODE_DISABLED
	$Name.text = racer_name
	$Name.modulate = colour
	if time > 0:
		@warning_ignore("integer_division")
		var mins: int = int(time)/60
		var secs: int = int(time)%60
		$Time.text = "%d:%02d"%[mins,secs]
		$Time.modulate = colour
