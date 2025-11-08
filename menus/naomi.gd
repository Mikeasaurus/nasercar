extends Control

signal _done

func run() -> void:
	show()
	process_mode = Node.PROCESS_MODE_INHERIT
	await _done
	process_mode = PROCESS_MODE_DISABLED
	hide()

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$NaomiCar.add_to_track($Path2D, [] as Array[TileMapLayer])
	$NaomiCar.make_local_cpu()
	$NaomiCar.go()

var _ending: bool = false
func _input(event: InputEvent) -> void:
	if not visible: return
	if _ending: return
	if (event is InputEventKey and event.is_action_pressed("a_key")) or \
	   (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed()):
		_ending = true
		var tween: Tween = create_tween()
		tween.tween_property(self,"modulate",Color.BLACK,1.0)
		await tween.finished
		_done.emit()

func _on_visibility_changed() -> void:
	if not visible: return
	modulate = Color.BLACK
	var tween: Tween = create_tween()
	tween.tween_property(self,"modulate",Color.WHITE,1.0)
	await tween.finished
