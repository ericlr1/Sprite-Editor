@tool
extends EditorPlugin

const EditorUI = preload("res://addons/sprite_editor/editor_UI.tscn")
var editor_ui_instance: Control

func _enter_tree() -> void:
	print("\n--- Plugin Initialization ---")
	
	# Instantiate UI
	editor_ui_instance = EditorUI.instantiate()
	print("UI instance created:", editor_ui_instance)
	
	# Add to main screen
	get_editor_interface().get_editor_main_screen().add_child(editor_ui_instance)
	print("UI added to main screen")
	
	# Initial visibility state
	_make_visible(false)
	print("Initial visibility set to false\n")

func _exit_tree() -> void:
	print("\n--- Plugin Cleanup ---")
	if editor_ui_instance:
		print("Removing UI instance")
		editor_ui_instance.queue_free()

func _has_main_screen() -> bool:
	print("Main screen check: true")
	return true

func _make_visible(visible: bool) -> void:
	print("\nVisibility change requested:", visible)
	if editor_ui_instance:
		editor_ui_instance.visible = visible
		print("Current UI visibility:", editor_ui_instance.visible)
		print("UI position:", editor_ui_instance.position)
		print("UI size:", editor_ui_instance.size)
	else:
		printerr("No UI instance exists!")

func _get_plugin_name() -> String:
	return "Sprite Editor"

func _get_plugin_icon() -> Texture2D:
	var icon = get_editor_interface().get_base_control().get_theme_icon("CanvasItem", "EditorIcons")
	print("\nLoading plugin icon:")
	print(" - Icon valid:", icon != null)
	print(" - Icon size:", icon.get_size() if icon else "N/A")
	return icon
