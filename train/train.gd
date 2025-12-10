extends Node2D
class_name Train

@export var num_cars: int = 8

var trackpaths: Array[PathFollow2D] = []
var traincars: Array[Node2D] = []

func _get_trackpath() -> Path2D:
	var p = get_parent()
	if p is Path2D:
		return p
	return null

func _get_configuration_warnings() -> PackedStringArray:
	if _get_trackpath() == null:
		return ["This scene must be the child of a Path2D."]
	return []

func _ready() -> void:
	# Add path following for trains.
	# Each PathFollow2D represents the position of the connectors between trains
	# (and very front and back).
	var path: Path2D = _get_trackpath()
	for i in range(num_cars+1):
		var p: PathFollow2D = PathFollow2D.new()
		p.rotates = false
		path.add_child.call_deferred(p,true)
		trackpaths.append(p)
	# Add trains to track.
	for i in range(num_cars):
		var t
		if i == 0:
			t = load("res://train/train_front.tscn").instantiate()
		else:
			t = load("res://train/train_car.tscn").instantiate()
		add_child.call_deferred(t,true)
		traincars.append(t)

func _process(delta: float) -> void:
	var old_angles: Array[float]
	for i in range(num_cars):
		old_angles.append(traincars[i].global_rotation)
	# Update positions of train car connectors.
	trackpaths[0].progress += delta * 200
	for i in range(1,num_cars+1):
		trackpaths[i].progress = trackpaths[i-1].progress - 100
	# Update train cars to align with the connectors.
	for i in range(num_cars):
		traincars[i].position = (trackpaths[i].position + trackpaths[i+1].position) / 2
		traincars[i].global_rotation = (trackpaths[i+1].position - trackpaths[i].position).angle()
