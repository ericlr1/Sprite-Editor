@tool
extends Control

const TAU = 2 * PI

class CanvasDrawing:
	extends Control
	var parent: Node
	
	func _init(p: Node):
		parent = p
	
	func _draw():
		if parent.is_drawing and parent.current_tool in [parent.TOOLS.RECTANGLE, parent.TOOLS.CIRCLE]:
			var end_pos = get_local_mouse_position()
			var preview_color = parent.current_color.darkened(0.2)
			
			match parent.current_tool:
				parent.TOOLS.RECTANGLE:
					var rect = Rect2(parent.shape_start_pos, end_pos - parent.shape_start_pos)
					draw_rect(rect, preview_color, 1.0, false)
				parent.TOOLS.CIRCLE:
					var radius = parent.shape_start_pos.distance_to(end_pos)
					draw_arc( parent.shape_start_pos, radius, 0, TAU, 32, preview_color, 1.0, false)

# Class-level variables
enum TOOLS {PENCIL, ERASER, FILL, RECTANGLE, CIRCLE, NONE}
var current_tool := TOOLS.NONE
var current_color := Color.BLACK
var brush_size := 5
var zoom_level := 1.0
var is_drawing := false
var last_position := Vector2.ZERO
var shape_start_pos := Vector2.ZERO
var current_image: Image
var current_texture: ImageTexture
var current_path := ""
var texture_update_pending = false
var canvas_drawing: CanvasDrawing 
var panning := false
var last_pan_position := Vector2.ZERO

@onready var scroll_container: ScrollContainer = $VBoxContainer/ScrollContainer
@onready var canvas: TextureRect = $VBoxContainer/ScrollContainer/Canvas
@onready var tools_container: HBoxContainer = $VBoxContainer/Toolbar/ToolsContainer
@onready var color_picker: ColorPickerButton = $VBoxContainer/Toolbar/ColorPickerButton
@onready var brush_size_label: Label = $VBoxContainer/Toolbar/HBoxContainer/CenterContainer2/Size
@onready var brush_size_slider: Slider = $VBoxContainer/Toolbar/HBoxContainer/CenterContainer/HSlider
@onready var save_dialog: FileDialog = $SaveDialog
@onready var open_dialog: FileDialog = $OpenDialog
@onready var new_dialog: Window = preload("res://addons/sprite_editor/NewDialog.tscn").instantiate()

func _ready():
	#TODO: Ver si quitamos esto -> self.visible = true
	
	# Remove existing CanvasDrawing node if it exists
	for child in scroll_container.get_children():
		if child is CanvasDrawing:
			child.queue_free()
	
	#Background
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.15, 0.15, 0.15)  # grey
	scroll_container.add_theme_stylebox_override("panel", bg_style)
	
	# Instansciate the CanvasDrawing
	canvas_drawing = CanvasDrawing.new(self)
	scroll_container.add_child(canvas_drawing)
	scroll_container.move_child(canvas_drawing, 0)
	
	_setup_theme()
	_setup_tools()
	new_image(256, 256)
	_update_zoom()
	
	# Signals setup
	color_picker.color_changed.connect(_on_color_changed)
	brush_size_slider.value_changed.connect(_on_brush_size_changed)
	canvas.gui_input.connect(_on_canvas_gui_input)
	$VBoxContainer/Toolbar/New.pressed.connect(_on_NewButton_pressed)
	$VBoxContainer/Toolbar/Open.pressed.connect(_on_OpenButton_pressed)
	$VBoxContainer/Toolbar/Save.pressed.connect(_on_SaveButton_pressed)
	
	# Brush size label update
	brush_size_label.text = "%d" % brush_size_slider.value
	
	# Add the NewDialog node
	add_child(new_dialog)
	new_dialog.hide()
	new_dialog.confirmed.connect(_on_new_dialog_confirmed)
	
	# Reset mouse to hande mouse inputs
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.focus_mode = Control.FOCUS_CLICK

func _setup_theme():
	var bg_color = get_theme_color("base_color", "Editor")
	# Panel styling
	var panel = StyleBoxFlat.new()
	panel.bg_color = bg_color.darkened(0.1)
	panel.border_color = bg_color.darkened(0.3)
	panel.set_border_width_all(2)
	add_theme_stylebox_override("panel", panel)
	
	# Button styling
	var button_style = StyleBoxFlat.new()
	button_style.bg_color = bg_color.darkened(0.2)
	button_style.set_border_width_all(1)
	button_style.set_border_color(bg_color.darkened(0.4))
	button_style.set_corner_radius_all(4)
	
	# Hover style
	var button_hover = button_style.duplicate()
	button_hover.bg_color = bg_color.darkened(0.15)
	
	# Add button theme overrides
	add_theme_stylebox_override("normal", button_style)
	add_theme_stylebox_override("hover", button_hover)
	add_theme_stylebox_override("pressed", button_hover)
	add_theme_stylebox_override("focus", button_style)

# Dynamic tools button creation
func _setup_tools():
	var tools = {
		"Pencil": TOOLS.PENCIL,
		"Eraser": TOOLS.ERASER,
		"Fill": TOOLS.FILL,
		"Rectangle": TOOLS.RECTANGLE,
		"Circle": TOOLS.CIRCLE
	}
	
	# Button group to switch by tool
	var button_group = ButtonGroup.new()
	
	for tool_name in tools:
		var btn = Button.new()
		btn.text = tool_name
		btn.toggle_mode = true
		btn.button_group = button_group
		btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		btn.connect("pressed", _on_tool_selected.bind(tools[tool_name]))
		tools_container.add_child(btn)

func new_image(width: int, height: int):
	current_image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	current_image.fill(Color(1, 1, 1, 1)) 
	current_texture = null
	
	# Reset zoom and texture
	zoom_level = 1.0
	_update_texture()
	_update_zoom()
	
	# Wait for UI to update
	await get_tree().process_frame
	
	# Force reset scroll to top-left
	scroll_container.scroll_horizontal = 0
	scroll_container.scroll_vertical = 0
	print("New image created. Size: %dx%d" % [width, height])

func load_texture(texture: ImageTexture):
	current_texture = texture
	current_image = current_texture.get_image()
	_update_texture()

func _update_texture():
	if current_image:
		# DEBUG: Print image data
		#print("Updating texture. Image format: ", current_image.get_format(), " | Size: ", current_image.get_size())
		# Create a new image on new_image
		if not current_texture:
			print("DEBUG: No current texture, creating a new one")
			current_texture = ImageTexture.new()
		
		current_texture.set_image(current_image)
		canvas.texture = current_texture
		canvas.queue_redraw()
		
		#print("Texture updated: ", current_texture)

func _update_zoom(zoom_anchor: Vector2 = Vector2.ZERO):
	if current_image:
		var img_size = current_image.get_size()
		var new_size = img_size * zoom_level
		
		# Update canvas dimensions
		canvas.custom_minimum_size = new_size
		canvas.size = new_size
		
		# Calculate new scroll position to maintain focus point
		if zoom_anchor != Vector2.ZERO:
			var target_x = zoom_anchor.x * zoom_level - (scroll_container.size.x / 2)
			var target_y = zoom_anchor.y * zoom_level - (scroll_container.size.y / 2)
			
			scroll_container.scroll_horizontal = clamp(target_x, 0, new_size.x - scroll_container.size.x)
			scroll_container.scroll_vertical = clamp(target_y, 0, new_size.y - scroll_container.size.y)
		
		print("Zoom Updated:", zoom_level, " | Canvas Size:", canvas.size)

func _get_canvas_position(screen_pos: Vector2) -> Vector2:
	var canvas_local_pos = canvas.get_local_mouse_position()
	var scroll_offset = Vector2(scroll_container.scroll_horizontal, scroll_container.scroll_vertical)
	return (canvas_local_pos + scroll_offset) / zoom_level

func _is_within_canvas(pos: Vector2) -> bool:
	return pos.x >= 0 && pos.x < current_image.get_width() && pos.y >= 0 && pos.y < current_image.get_height()

func _draw_pixel(pos: Vector2, color: Color):
	#current_image.lock()									# Block the image to safe-write
	for x in range(brush_size):								# Width iteration (Square)
		for y in range(brush_size):							# Height iteration (Square)
			var px = pos.x - brush_size/2 + x				# Center the circle arround the pos
			var py = pos.y - brush_size/2 + y
			if _is_within_canvas(Vector2(px, py)):			# Verify that the pixel to paint is in the canvas
				current_image.set_pixel(px, py, color)		# Change the color of the pixel
	#current_image.unlock()									# Unblock the image

func _draw_line(start: Vector2, end: Vector2, color: Color):
	var points = _get_line_points(start, end)				# Get the points in the line
	for point in points:									# Iterate all the points in the line
		_draw_pixel(point, color)							# Changes the color of the pixels in the line like the pencil
	texture_update_pending = true

func _get_line_points(start: Vector2, end: Vector2) -> Array:
	# === Bresenham Algorithm ===
	var points = []
	var dx := absi(end.x - start.x) # Distance in X
	var dy := -absi(end.y - start.y) # Distance in Y
	var sx := 1 if start.x < end.x else -1
	var sy := 1 if start.y < end.y else -1
	var err = dx + dy
	
	var x = start.x # Starting X pos
	var y = start.y # Starting Y pos
	
	while true: # Infinite loop to paint all the points
		points.append(Vector2(x, y)) # Add the actual point to the vector of points
		if x == end.x && y == end.y: # If it's the last point exit the loop
			break
		var e2 = 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy
	return points # Return tall the points in the line

func _flood_fill(pos: Vector2):
	var target_color = current_image.get_pixelv(pos) # Gets the color where the user clicked (the one thah should be changed to the current_color)
	if target_color == current_color: # If the clicked color is the same as the current_color skip all
		return

	# (TODO: Maybe change to Scanline in the future)
	# === BFS Algorithm to fill the shape === 
	var queue = [pos] # Init a queue with the initial position
	#current_image.lock() # Blocks the iname to safe-write on it
	
	# Loop the queue until it's empty
	while not queue.is_empty():
		var p = queue.pop_front() # Extract the firs element of the queue
		if _is_within_canvas(p) && current_image.get_pixelv(p) == target_color: # Verify that the pixel in inside the canvas and the pixel is the same color as the target
			current_image.set_pixelv(p, current_color) # Change the color of the selected pixel
			
			# Add the next 4 directions to the queue
			queue.append(Vector2(p.x + 1, p.y)) # Right
			queue.append(Vector2(p.x - 1, p.y)) # Left
			queue.append(Vector2(p.x, p.y + 1)) # Bottom
			queue.append(Vector2(p.x, p.y - 1)) # Up
	
	# Unlock the inage and update the texture
	#current_image.unlock() 
	_update_texture() # TODO: Revisar si esto está haciendo que hayan dos update_texture al soltar el click

func _draw_rect_shape(start: Vector2, end: Vector2):
	#current_image.lock() # Blocks the iname to safe-write on it
	var rect = Rect2i(start, end - start).abs() # Create the rectangle
	for x in rect.size.x: # Iterate the columns
		for y in rect.size.y: # Iterate the rows
			var pos = Vector2(rect.position.x + x, rect.position.y + y) # Calculates the pixel position
			if _is_within_canvas(pos): # Verify if the pixel inside the canvas
				current_image.set_pixelv(pos, current_color) # Change teh color of the pixel
	#current_image.unlock() # Unlock the inage

func _draw_circle_shape(center: Vector2, radius: float):
	#current_image.lock() # Blocks the iname to safe-write on it
	var radius_sq = pow(radius, 2) # Calculate the power of the radius
	for x in range(center.x - radius, center.x + radius): # Iterate the columns (Square)
		for y in range(center.y - radius, center.y + radius): # Iterate the rows (Square)
			var pos = Vector2(x, y) # Pixel position
			if _is_within_canvas(pos) && pos.distance_squared_to(center) <= radius_sq: # Verify that the pixel is in the canvas and inside the circle
				current_image.set_pixelv(pos, current_color) # Change the color of the pixel
	#current_image.unlock() # Unlock the inage

# TODO: Fix the double call for the zoom function when zooming with the mouse wheel
func _on_canvas_gui_input(event):
	# Zoom with mouse wheel
	if event.ctrl_pressed:
		if event is InputEventMouseButton:
			var viewport = get_viewport()
			var mouse_pos = event.position
			
			# Calculate zoom anchor point (canvas-relative)
			var canvas_rect = canvas.get_global_rect()
			var zoom_anchor = (mouse_pos - canvas_rect.position + Vector2(scroll_container.scroll_horizontal, scroll_container.scroll_vertical)) / zoom_level
			print("Zoom Anchor: ", zoom_anchor)
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				zoom_level = clamp(zoom_level * 1.1, 0.1, 20.0)
				_update_zoom(zoom_anchor)
				get_viewport().set_input_as_handled()
				return
			
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				zoom_level = clamp(zoom_level / 1.1, 0.1, 20.0)
				_update_zoom(zoom_anchor)
				get_viewport().set_input_as_handled()
				return
		return  
	
	# Handle mouse click
	if event is InputEventMouseButton:
		# === Pencil Tool ===
		if event.button_index == MOUSE_BUTTON_LEFT and current_tool == TOOLS.PENCIL:
			if event.pressed:
				is_drawing = true
				last_position = _get_canvas_position(event.position)
				_draw_pixel(last_position, current_color)
				texture_update_pending = true
			else:
				is_drawing = false
		# === Eraser Tool ===
		elif event.button_index == MOUSE_BUTTON_LEFT and current_tool == TOOLS.ERASER:
			if event.pressed:
				is_drawing = true
				last_position = _get_canvas_position(event.position)
				_draw_pixel(last_position, Color.from_hsv(0, 0, 0, 0))
				texture_update_pending = true
			else:
				is_drawing = false
		# === Fill bucket Tool ===
		elif event.button_index == MOUSE_BUTTON_LEFT and current_tool == TOOLS.FILL:
			if event.pressed:
				is_drawing = true
				last_position = _get_canvas_position(event.position)
				_flood_fill(last_position)
				texture_update_pending = true
			else:
				is_drawing = false
	
	# Update texture while painting
	if event is InputEventMouseMotion and is_drawing:
		#print("Updated texture while painting")
		var current_pos = _get_canvas_position(event.position)
		if current_pos.distance_to(last_position) >= 0.5: 
			if current_tool == TOOLS.PENCIL:
				_draw_line(last_position, current_pos, current_color) # Draw a line between the last two point
			elif current_tool == TOOLS.ERASER:
				_draw_line(last_position, current_pos, Color.from_hsv(0, 0, 0, 0)) # Draw a line between the last two point
			last_position = current_pos
			texture_update_pending = true
	

func _on_tool_selected(tool: TOOLS):
	current_tool = tool

func _on_color_changed(color: Color):
	current_color = color

func _on_brush_size_changed(value: float):
	print("Brush size changed: ", value)
	brush_size_label.text = "%d" % value
	brush_size = value

func _on_new_dialog_confirmed(width: int, height: int):
	new_image(width, height)

func _on_NewButton_pressed():
	print("New button pressed")
	new_dialog.popup_centered()
	await get_tree().process_frame
	$VBoxContainer/Toolbar/New.grab_focus()
	print("New button pressed - END")

func _on_OpenButton_pressed():
	# Show Open dialog
	print("Open button pressed")
	if open_dialog:
		open_dialog.popup_centered()
	else:
		push_error("OpenDialog not initialized!")
		OS.alert("Error: Open dialog not configured", "Critical Error")

func _on_SaveButton_pressed():
	# Show Save dialog
	print("Save button pressed")
	if save_dialog:
		save_dialog.popup_centered()
	else:
		push_error("SaveDialog not initialized!")
		OS.alert("Error: Save dialog not configured", "Critical Error")

func _on_SaveDialog_file_selected(path: String):
	# Save the image in the "path" as a .png
	if not current_image:
		OS.alert("No image to save!", "Save Error")
		return
	
	if path.get_extension().to_lower() != "png":
		OS.alert("Only PNG format supported!", "Format Error")
		return
	
	var save_result = current_image.save_png(path)
	if save_result != OK:
		push_error("Failed to save PNG (Error code: %d)" % save_result)
		OS.alert("Failed to save image!\nCheck file permissions and path.", "Save Error")
		return
	
	# Update the resource of the editor
	_notify_resource_update(path)
	OS.alert("Image saved successfully!", "Success")

func _on_OpenDialog_file_selected(path: String):
	# Update the open file path
	if not FileAccess.file_exists(path):
		OS.alert("File does not exist!", "Open Error")
		return
	
	# Load the image from a file
	var loaded_image = Image.load_from_file(path)
	if loaded_image == null:
		push_error("Failed to load image from: " + path)
		OS.alert("Invalid image file format!", "Open Error")
		return
	
	current_image = loaded_image
	
	# Update the current visible texture
	_update_texture()
	
	# Update the resource of the editor
	_notify_resource_update(path)
	OS.alert("Image loaded successfully!", "Success")

func _notify_resource_update(path: String):
	# Scan the files of the project
	var fs = EditorInterface.get_resource_filesystem()
	fs.scan()
	
	# Scan the sources of the resources
	fs.scan_sources()
	
	# Verify the resource exists
	if not ResourceLoader.exists(path):
		push_error("Resource not found: " + path)
		return
	
	# Open the resource in the editor
	var resource = load(path)
	if resource:
		EditorInterface.edit_resource(resource)
	else:
		push_error("Failed to load resource: " + path)

func _input(event):
	# Debug key F to center the canvas and reset zoom
	if event is InputEventKey and event.pressed and event.keycode == KEY_F and self.is_visible_in_tree():
		await get_tree().process_frame
		
		# Reset zoom
		zoom_level = 1.0
		_update_zoom()
		
		# Get viewport and canvas sizes
		var viewport_size = scroll_container.size
		var canvas_size = canvas.size
		
		# Calculate centered scroll
		var target_h = max(0, (canvas_size.x - viewport_size.x) / 2)
		var target_v = max(0, (canvas_size.y - viewport_size.y) / 2)
		
		# Apply H/V scroll
		scroll_container.scroll_horizontal = target_h
		scroll_container.scroll_vertical = target_v
		print("Centered at: ", Vector2(target_h, target_v))
	

func _unhandled_input(event: InputEvent):
	# Pan with wheel mouse click
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				# Start panning
				panning = true
				last_pan_position = get_global_mouse_position()
				Input.set_default_cursor_shape(Input.CURSOR_DRAG)
				get_viewport().set_input_as_handled()
			else:
				# End panning
				panning = false
				Input.set_default_cursor_shape(Input.CURSOR_ARROW)
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and panning:
		# Panning moving
		var current_pos = get_global_mouse_position() # Get mouse global pos
		var delta = last_pan_position - current_pos # Calculate the diference of positions
		scroll_container.scroll_horizontal += delta.x # Scroll X acording to dX
		scroll_container.scroll_vertical += delta.y #Scroll Y acording to dY
		last_pan_position = current_pos
		get_viewport().set_input_as_handled()

func _process(delta):
	if texture_update_pending:
		_update_texture()
		texture_update_pending = false
		# Limit to 60 FPS
		await get_tree().create_timer(1.0/60.0).timeout

func _exit_tree():
	# Cleanup CanvasDrawing node
	if canvas_drawing and is_instance_valid(canvas_drawing):
		canvas_drawing.queue_free()
