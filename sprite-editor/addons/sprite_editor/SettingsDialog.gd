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

func _on_ok_pressed():
	emit_signal("zoom_sensitivity_changed", $VBoxContainer/ZoomSlider/HSlider.value)
	emit_signal("panning_sensitivity_changed", $VBoxContainer/PanningSlider/HSlider.value)
	emit_signal("theme_selected", $VBoxContainer/ThemeSelector/OptionButton.text)
	hide()

func set_initial_values(zoom_value: float, pan_value: float, theme_name: String):
	$VBoxContainer/ZoomSlider/HSlider.value = zoom_value
	$VBoxContainer/PanningSlider/HSlider.value = pan_value
	$VBoxContainer/ThemeSelector/OptionButton.select(available_themes.find(theme_name))

func _on_cancel_pressed():
	hide()
