extends Control

func run () -> void:
	show()
	await $MarginContainer/CenterContainer/VBoxContainer/BackButton.pressed
	hide()

func _ready() -> void:
	# Pad out the names of the tabs (the default layout puts the labels too close together).
	var tc: TabContainer = $MarginContainer/CenterContainer/VBoxContainer/TabContainer
	for i in range(tc.get_tab_count()):
		var label: String = tc.get_tab_title(i)
		label = "  " + label + "  "
		tc.set_tab_title(i, label)
