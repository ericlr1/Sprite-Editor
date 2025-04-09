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
var update_cooldown = 0.0

# === Plugin Settings ===
var panning_sensitivity := 1.2
var zoom_sensitivity := 0.05 # Closer to 0 (Smother scroll) and closer to 1 (Rough scroll)

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
	# Remove existing CanvasDrawing node if it exists
	for child in scroll_container.get_children():
		if child is CanvasDrawing:
			child.queue_free()
	# Instansciate the CanvasDrawing
	canvas_drawing = CanvasDrawing.new(self)
	scroll_container.add_child(canvas_drawing)
	scroll_container.move_child(canvas_drawing, 0)
	
	#Background
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.15, 0.15, 0.15)  # grey
	scroll_container.add_theme_stylebox_override("panel", bg_style)
	
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
	
	# Connect save dialog signals
	save_dialog.file_selected.connect(_on_SaveDialog_file_selected)
	
	# Setup OpenDialog
	open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	open_dialog.add_filter("*.png", "PNG Images")
	open_dialog.file_selected.connect(_on_OpenDialog_file_selected)

	# Add the NewDialog node
	add_child(new_dialog)
	new_dialog.hide()
	new_dialog.confirmed.connect(_on_new_dialog_confirmed)
	
	# Brush size label update
	brush_size_label.text = "%d" % brush_size_slider.value
	
	# Reset mouse to hande mouse inputs
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.focus_mode = Control.FOCUS_CLICK
	
	# Setup anti-aliasing
	get_viewport().msaa_2d = Viewport.MSAA_DISABLED  # No AA to have perfect pixels
	get_viewport().canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST

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
	scroll_container.queue_redraw()
	canvas.queue_redraw()
	get_viewport().set_input_as_handled()
	print("New image created. Size: %dx%d" % [width, height])

func load_texture(texture: ImageTexture):
	current_texture = texture
	current_image = current_texture.get_image()
	_update_texture()

func _update_texture():
	if current_image:
		# If not a RGBA8 format, convert it to RGBA8
		if current_image.get_format() != Image.FORMAT_RGBA8:
			current_image.convert(Image.FORMAT_RGBA8)
		
		# DEBUG: Print image data
		#print("Updating texture. Image format: ", current_image.get_format(), " | Size: ", current_image.get_size())
		# Create a new image on new_image
		if not current_texture:
			print("DEBUG: No current texture, creating a new one")
			current_texture = ImageTexture.new()
		
		current_texture.set_image(current_image)
		canvas.texture = current_texture
		canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		canvas.queue_redraw()
		
		#print("Texture updated: ", current_texture)

func _update_zoom(zoom_anchor: Vector2 = Vector2.ZERO):
	if current_image:
		var prev_zoom = zoom_level
		var new_size = current_image.get_size() * zoom_level
		
		# Update canvas size first
		canvas.custom_minimum_size = new_size
		canvas.size = new_size
		
		if zoom_anchor != Vector2.ZERO:
			# Calculate new scroll to keep the same point under the cursor
			var ratio = zoom_level / prev_zoom
			scroll_container.scroll_horizontal = (zoom_anchor.x * ratio - scroll_container.size.x / 2) * zoom_level
			scroll_container.scroll_vertical = (zoom_anchor.y * ratio - scroll_container.size.y / 2) * zoom_level
		print("Zoom Updated:", zoom_level, " | Canvas Size:", canvas.size)

func _is_within_canvas(pos: Vector2) -> bool:
	return pos.x >= 0 && pos.x < current_image.get_width() && pos.y >= 0 && pos.y < current_image.get_height()

func _draw_pixel(pos: Vector2, color: Color):
	#current_image.lock()									# Block the image to safe-write
	var radius = brush_size / 2.0
	for x in range(brush_size):								# Width iteration (Circle)
		for y in range(brush_size):							# Height iteration (Circle)
			var px = pos.x - brush_size/2 + x				# Center the circle arround the pos
			var py = pos.y - brush_size/2 + y
			if Vector2(x - radius, y - radius).length_squared() <= radius * radius:
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
	# Get image dimensions for boundary checks
	var img_width = current_image.get_width()
	var img_height = current_image.get_height()
	
	# Calculate clamped rectangle coordinates
	var rect = Rect2(
		# Clamp start coordinates to image boundaries
		Vector2(clamp(min(start.x, end.x), 0, img_width), clamp(min(start.y, end.y), 0, img_height)),
		# Clamp dimensions to prevent overflow
		Vector2(clamp(abs(end.x - start.x), 0, img_width), clamp(abs(end.y - start.y), 0, img_height))
	)
	
	current_image.fill_rect(rect, current_color)

func _draw_circle_shape(center: Vector2, radius: float):
	var img_width = current_image.get_width()
	var img_height = current_image.get_height()
	
	# Optimized bounds calculation (clamped to image edges)
	var start_x = clamp(center.x - radius, 0, img_width)
	var start_y = clamp(center.y - radius, 0, img_height)
	var end_x = clamp(center.x + radius, 0, img_width)
	var end_y = clamp(center.y + radius, 0, img_height)
	
	var radius_sq = radius * radius  # Pre-calculate squared radius
	
	# Batch pixel update loop
	for x in range(start_x, end_x + 1): # Iterate Rows
		for y in range(start_y, end_y + 1): # Iterate Columns
			var pos = Vector2i(x, y)
			if pos.distance_squared_to(center) <= radius_sq:
				current_image.set_pixelv(pos, current_color)

# TODO: Fix the double call for the zoom function when zooming with the mouse wheel
func _on_canvas_gui_input(event):
	# ======================== ZOOM WITH CTRL + MOUSE WHEEL ========================
	if event.ctrl_pressed and event is InputEventMouseButton:
		var viewport = get_viewport()
		var mouse_pos = event.position

		# Calculate zoom anchor point relative to canvas and scroll offset
		var canvas_rect = canvas.get_global_rect()
		var zoom_anchor = (
			(event.global_position - canvas_rect.position + 
			Vector2(scroll_container.scroll_horizontal, scroll_container.scroll_vertical)) 
			/ zoom_level
		)

		# Zoom in (scroll up)
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_level = clamp(zoom_level * (1 + zoom_sensitivity), 0.1, 20.0)
			_update_zoom(zoom_anchor)
			get_viewport().set_input_as_handled()
			return

		# Zoom out (scroll down)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_level = clamp(zoom_level / (1 + zoom_sensitivity), 0.1, 20.0)
			_update_zoom(zoom_anchor)
			get_viewport().set_input_as_handled()
			return

	# ======================== SMOOTH PANNING ========================
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		panning = event.pressed

		if panning:
			# Begin panning – store starting mouse position
			last_pan_position = event.global_position
			Input.set_default_cursor_shape(Input.CURSOR_DRAG)
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)  # Ensure cursor stays visible
		else:
			# End panning – restore cursor
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)

		get_viewport().set_input_as_handled()
		return

	elif event is InputEventMouseMotion and panning:
		# Compute movement delta with smoothing factor (inverse direction of mouse)
		var delta = (event.global_position - last_pan_position) * zoom_level * panning_sensitivity
	
		# Apply H/V scroll
		scroll_container.scroll_horizontal -= delta.x
		scroll_container.scroll_vertical -= delta.y
	
   	 	# Scroll should be inside the limits
		scroll_container.scroll_horizontal = clamp(
			scroll_container.scroll_horizontal, 
			0, 
			max(0, canvas.size.x - scroll_container.size.x)
		)
		scroll_container.scroll_vertical = clamp(
			scroll_container.scroll_vertical, 
			0, 
			max(0, canvas.size.y - scroll_container.size.y)
		)

		# Update position for next frame
		last_pan_position = event.global_position
		get_viewport().set_input_as_handled()
		return

	# ======================== DRAWING TOOLS ========================
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var canvas_pos = _get_canvas_position(event.position)

		# Handle pencil and eraser tools
		if current_tool == TOOLS.PENCIL or current_tool == TOOLS.ERASER:
			is_drawing = event.pressed
			last_position = canvas_pos

			if event.pressed:
				_draw_pixel_smooth(canvas_pos, current_color if current_tool == TOOLS.PENCIL else Color.TRANSPARENT)

		# Handle fill tool
		elif current_tool == TOOLS.FILL and event.pressed:
			_flood_fill(canvas_pos)

		# Handle rectangle and circle shape tools
		elif current_tool in [TOOLS.RECTANGLE, TOOLS.CIRCLE]:
			if event.pressed:
				shape_start_pos = canvas_pos
				is_drawing = true
			else:
				_finalize_shape(canvas_pos)  # Draw final shape

		texture_update_pending = true  # Mark canvas for redraw

	# Continuous drawing while moving mouse
	elif event is InputEventMouseMotion and is_drawing:
		var current_pos = _get_canvas_position(event.position)

		# Use point interpolation for smooth drawing
		if current_tool in [TOOLS.PENCIL, TOOLS.ERASER]:
			var points = _get_smoothed_points(last_position, current_pos)
			for point in points:
				_draw_pixel_smooth(point, current_color if current_tool == TOOLS.PENCIL else Color.TRANSPARENT)
			last_position = current_pos

		texture_update_pending = true

	# Final texture update if anything was drawn
	if texture_update_pending:
		_update_texture()
		texture_update_pending = false

# Convert screen coordinates to zoomed canvas coordinates
func _get_canvas_position(screen_pos: Vector2) -> Vector2:
	# Get mouse position relative to scroll container's viewport
	var viewport_pos = scroll_container.get_global_transform().affine_inverse() * get_global_mouse_position()
	# Convert to canvas coordinates (zoomed image space)
	var canvas_pos = (viewport_pos + Vector2(scroll_container.scroll_horizontal, scroll_container.scroll_vertical)) / zoom_level
	return canvas_pos
	
# Draw a single pixel with smoothing (anti-aliasing)
func _draw_pixel_smooth(pos: Vector2, color: Color):
	# Calculate the brush radius based on brush size
	var radius = brush_size / 2.0

	# Define the square area around the center position `pos` where the brush will affect pixels
	var start_x = int(pos.x - radius)
	var start_y = int(pos.y - radius)
	var end_x = int(pos.x + radius)
	var end_y = int(pos.y + radius)
	
	# Loop through every pixel in the square brush area
	for x in range(start_x, end_x + 1):
		for y in range(start_y, end_y + 1):
			var pixel_pos = Vector2i(x, y)
			# Only affect pixels that are inside the canvas boundaries
			if _is_within_canvas(pixel_pos):
				# Calculate distance from current pixel to the center of the brush
				var distance = Vector2(x - pos.x, y - pos.y).length()
				# If the pixel is within the circular brush radius
				if distance <= radius:
					# Calculate blending weight based on how close the pixel is to the center
					# Closer pixels get more of the new color, farther ones get less (soft edge effect)
					var weight = 1.0 #- (distance / radius) #TODO: Veri si acabamos haciendo esto para el pincel o algo
					var existing_color = current_image.get_pixelv(pixel_pos) # Get the existing pixel color from the canvas
					
					# Blend the existing color with the brush color using the weight, and apply it
					current_image.set_pixelv(pixel_pos, existing_color.lerp(color, weight))

# Generate intermediate points between two positions for smooth lines
func _get_smoothed_points(start: Vector2, end: Vector2) -> Array:
	var points = []
	var distance = start.distance_to(end)
	var steps = clamp(int(distance * 2.5), 2, 20)  # More distance = more steps

	for i in range(steps + 1):
		var t = float(i) / steps
		points.append(start.lerp(end, t))  # Linear interpolation between points

	return points

# Finalize drawing of shapes (rectangle or circle)
func _finalize_shape(end_pos: Vector2):
	match current_tool:
		TOOLS.RECTANGLE:
			_draw_rect_shape(shape_start_pos, end_pos)
		TOOLS.CIRCLE:
			var radius = shape_start_pos.distance_to(end_pos)
			_draw_circle_shape(shape_start_pos, radius)
	_update_texture()


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
	# Visual feedback
	$VBoxContainer/Toolbar/Open.modulate = Color.SKY_BLUE
	await get_tree().create_timer(0.2).timeout
	$VBoxContainer/Toolbar/Open.modulate = Color.WHITE
	
	# Show dialog
	open_dialog.popup_centered_ratio(0.8)

func _on_OpenDialog_file_selected(path: String):
	if not FileAccess.file_exists(path):
		OS.alert("File not found!", "Open Error")
		return
	
	var img = Image.new()
	var err = img.load(path)
	
	# Check for errors
	if err != OK:
		OS.alert("Failed to load image!\nError code: %d" % err, "Open Error")
		return
	
	# Update the state
	current_image = img
	current_path = path
	_update_texture()
	_update_zoom()
	print("Image loaded successfully!")

func _on_SaveButton_pressed():
	# Visual feedback
	$VBoxContainer/Toolbar/Save.modulate = Color.GREEN
	await get_tree().create_timer(0.2).timeout
	$VBoxContainer/Toolbar/Save.modulate = Color.WHITE
	
	# Configure save dialog
	save_dialog.clear_filters()
	save_dialog.add_filter("*.png", "PNG Images")
	save_dialog.current_dir = "res://" if current_path.is_empty() else current_path.get_base_dir()
	save_dialog.current_file = "new_sprite.png" if current_path.is_empty() else current_path.get_file()
	save_dialog.popup_centered()

func _on_SaveDialog_file_selected(path: String):
	# Validate image exists
	if not current_image:
		OS.alert("No image to save!", "Save Error")
		return
	
	# Clean path format
	var clean_path = path.replace("\\", "/").simplify_path()
	
	# Validate directory permissions
	var dir = DirAccess.open(clean_path.get_base_dir())
	if not dir:
		OS.alert("Invalid save location or insufficient permissions!", "Save Error")
		return
	
	# Validate file extension
	if clean_path.get_extension().to_lower() != "png":
		OS.alert("Only PNG format supported!", "Format Error")
		return
	
	# Save operation
	var save_result = current_image.save_png(clean_path)
	
	if save_result != OK:
		var error_msg = "Failed to save image!\nError code: %d" % save_result
		push_error(error_msg)
		OS.alert(error_msg, "Save Error")
		return
	
	# Update current path and refresh
	current_path = clean_path
	_notify_resource_update(clean_path)
	print("Image saved successfully!")	

func _on_save_complete(path: String, result: int):
	if result != OK:
		push_error("Failed to save PNG (Error code: %d)" % result)
		OS.alert("Failed to save image!\nCheck file permissions and path.", "Save Error")
		return
	
	# Update editor resources
	_notify_resource_update(path)
	OS.alert("Image saved successfully!", "Success")

func _notify_resource_update(path: String):
	# Force filesystem refresh
	var fs = EditorInterface.get_resource_filesystem()
	fs.scan()
	
	# Add slight delay for filesystem to recognize changes
	await get_tree().create_timer(0.5).timeout
	
	# Open resource if exists
	if ResourceLoader.exists(path):
		var resource = load(path)
		EditorInterface.edit_resource(resource)
		print("Resource updated in editor: ", path)

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

func _process(delta):
	if texture_update_pending:
		update_cooldown += delta
		if update_cooldown >= 1.0 / 60.0:  # Limit to 60 FPS
			_update_texture()
			texture_update_pending = false
			update_cooldown = 0.0

func _exit_tree():
	# Cleanup CanvasDrawing node
	if canvas_drawing and is_instance_valid(canvas_drawing):
		canvas_drawing.queue_free()
