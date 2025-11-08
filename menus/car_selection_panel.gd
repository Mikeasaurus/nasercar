extends PanelContainer
class_name CarSelectionPanel

@export var car_scene: PackedScene
signal selected

var car: Car
var selectable: bool = true

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if car_scene !=  null:
		car = car_scene.instantiate()
		$SubViewportContainer/SubViewport.add_child(car)
		car.position = Vector2(75,75)
		car.process_mode = Node.PROCESS_MODE_DISABLED

func select () -> void:
	var stylebox: StyleBoxFlat = get_theme_stylebox("panel")
	stylebox.border_color = Color.hex(0xffffffff)

func unselect() -> void:
	var stylebox: StyleBoxFlat = get_theme_stylebox("panel")
	stylebox.border_color = Color.hex(0xffffff00)

# Car taken by somebody else; not available for selection.
func disable() -> void:
	selectable = false
	for node in ["Body","Wheels/FrontLeft", "Wheels/FrontRight", "Wheels/RearLeft", "Wheels/RearRight"]:
		car.get_node(node).modulate = Color.hex(0x555555ff)
func enable() -> void:
	selectable = true
	for node in ["Body","Wheels/FrontLeft", "Wheels/FrontRight", "Wheels/RearLeft", "Wheels/RearRight"]:
		car.get_node(node).modulate = Color.WHITE
	$SubViewportContainer/SubViewport/Name.hide()

# Put text overlay on a panel.
func overlay(text: String) -> void:
	$SubViewportContainer/SubViewport/Name.text = text
	$SubViewportContainer/SubViewport/Name.show()
func no_overlay() -> void:
	$SubViewportContainer/SubViewport/Name.hide()

func _on_mouse_entered() -> void:
	if not selectable: return
	var stylebox: StyleBoxFlat = get_theme_stylebox("panel")
	stylebox.bg_color = 0x777777ff

func _on_mouse_exited() -> void:
	var stylebox: StyleBoxFlat = get_theme_stylebox("panel")
	stylebox.bg_color = 0x77777700

func _on_gui_input(event: InputEvent) -> void:
	if not selectable: return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			selected.emit()
