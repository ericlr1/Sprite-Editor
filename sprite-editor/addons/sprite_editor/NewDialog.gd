@tool
extends Window

signal confirmed(width, height)

func _ready():
	hide()  
	$VBoxContainer/Buttons/OKButton.pressed.connect(_on_ok_pressed)
	$VBoxContainer/Buttons/CancelButton.pressed.connect(_on_cancel_pressed)

func _on_ok_pressed():
	var width = int($VBoxContainer/Width/WidthSpinBox.value)
	var height = int($VBoxContainer/Height/HeightSpinBox.value)
	confirmed.emit(width, height)
	hide()

func _on_cancel_pressed():
	hide()
