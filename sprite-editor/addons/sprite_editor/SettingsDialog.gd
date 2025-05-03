@tool
extends Window

signal theme_selected(theme_name)
signal zoom_sensitivity_changed(value)
signal panning_sensitivity_changed(value)

var available_themes = ["Dark", "Light", "Blue"]

func _ready():
	hide()
	$VBoxContainer/Buttons/OKButton.pressed.connect(_on_ok_pressed)
	$VBoxContainer/Buttons/CancelButton.pressed.connect(_on_cancel_pressed)
	
	# Configure avalible themes
	var theme_selector = $VBoxContainer/ThemeSelector/OptionButton
	for theme in available_themes:
		theme_selector.add_item(theme)
	
	# Setup initial values
	$VBoxContainer/ZoomSlider/HSlider.value = get_parent().zoom_sensitivity
	$VBoxContainer/PanningSlider/HSlider.value = get_parent().panning_sensitivity

func _on_ok_pressed():
	emit_signal("zoom_sensitivity_changed", $VBoxContainer/ZoomSlider/HSlider.value)
	emit_signal("panning_sensitivity_changed", $VBoxContainer/PanningSlider/HSlider.value)
	emit_signal("theme_selected", $VBoxContainer/ThemeSelector/OptionButton.text)
	hide()

func _on_cancel_pressed():
	hide()
