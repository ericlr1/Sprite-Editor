@tool
extends Control

const TAU = 2 * PI

class CanvasDrawing:
	extends Control
	var parent: Node
	
	func _init(p: Node):
		parent = p
		print("CanvasDrawing._init(parent: %s)" % p.name)
	
	func _draw():
		print("CanvasDrawing._draw() - is_drawing: %s, tool: %s" % [parent.is_drawing, parent.TOOLS.keys()[parent.current_tool]])
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

# === Class-level variables ===

# Enumeration of available tools in the editor
enum TOOLS {PENCIL, ERASER, FILL, RECTANGLE, CIRCLE, EYE_DROPPER, NONE}

# Editor state variables
var current_tool := TOOLS.NONE              # Currently selected tool
var current_color := Color.BLACK            # Current drawing color
var brush_size := 5                         # Size of the brush
var zoom_level := 1.0                       # Current zoom level on the canvas
var is_drawing := false                     # Whether the user is currently drawing
var last_position := Vector2.ZERO           # Last mouse position (for drawing strokes)
var shape_start_pos := Vector2.ZERO         # Start position when drawing shapes
var current_image: Image                    # The image being edited
var current_texture: ImageTexture           # Texture representation of the image
var current_path := ""                      # File path of the currently loaded/saved image
var texture_update_pending = false          # Flag to indicate if the texture needs an update
var canvas_drawing: CanvasDrawing           # Custom drawing logic or helper object
var panning := false                        # Whether the user is currently panning the view
var last_pan_position := Vector2.ZERO       # Last mouse position used for panning
var update_cooldown = 0.0                   # Time remaining before allowing another texture update
var _brush_offsets := []                    # Used to store offsets for brush stamping

# === Plugin Settings ===

var settings_dialog: Window = preload("res://addons/sprite_editor/SettingsDialog.tscn").instantiate()
var panning_sensitivity := 1.2              # Sensitivity when panning the canvas
var zoom_sensitivity := 0.05                # Zoom scroll sensitivity (lower = smoother)
var current_theme := "Dark"                 # Selected theme in settings

# === UI Node References (initialized when the scene is ready) ===

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
	print("_ready() - Initializing editor")
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
	$VBoxContainer/Toolbar/Eyedropper.pressed.connect(_on_eyedropper_pressed)
	
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
	
	_precompute_brush_offsets()
	
	# Setup settings window
	add_child(settings_dialog)
	settings_dialog.hide()
	settings_dialog.theme_selected.connect(_on_theme_selected)
	settings_dialog.zoom_sensitivity_changed.connect(_on_zoom_sensitivity_changed)
	settings_dialog.panning_sensitivity_changed.connect(_on_panning_sensitivity_changed)

func _setup_theme():
	print("_setup_theme()")
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
	
	print("_setup_tools() - Creating %d tools" % tools.size())

func new_image(width: int, height: int):
	print("new_image(width: %d, height: %d)" % [width, height])
	current_image = null  # Reset first


	
	current_image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	current_image.fill(Color(1, 1, 1, 1)) 
	current_texture = null
	
	# Reset zoom and texture
	zoom_level = 1.0
	_update_texture()
	_update_zoom()
	
	# Wait for UI to update
	#await get_tree().process_frame
	
	# Force reset scroll to top-left
	scroll_container.queue_redraw()
	canvas.queue_redraw()
	get_viewport().set_input_as_handled()
	print("New image created. Size: %dx%d" % [width, height])

func load_texture(texture: ImageTexture):
	print("load_texture(texture: %s, size: %s)" % [texture.resource_path, texture.get_size()])
	current_texture = texture
	current_image = current_texture.get_image()
	_update_texture()

func _update_texture():
	if current_image:
		# -- If we already have an image loaded, proceed --

		# Re‑use a saved ImageTexture instead of instantiating a new one
		# every frame (avoids constant allocation/GC overhead).
		if not current_texture:
			current_texture = ImageTexture.new()      # create it once
			print("DEBUG: Created new ImageTexture")  # helpful log message

		# Copy the pixel data from current_image into the texture object
		current_texture.set_image(current_image)

		# Push the texture to the CanvasItem we’re drawing on
		canvas.texture = current_texture

		# Use the nearest‑neighbor filter so pixels stay crisp (no smoothing)
		canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

		# If no redraw is already scheduled, ask Godot to repaint this node.
		# This prevents redundant queue_redraw() calls in the same frame.
		if not texture_update_pending:
			canvas.queue_redraw()

func _update_zoom(zoom_anchor: Vector2 = Vector2.ZERO):
	if current_image:
		var prev_zoom = zoom_level
		var new_size = current_image.get_size() * zoom_level
		
		print("_update_zoom(zoom_level: %.2f, anchor: %s)" % [zoom_level, zoom_anchor])
		
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
	var res = pos.x >= 0 && pos.x < current_image.get_width() && pos.y >= 0 && pos.y < current_image.get_height()
	print("_is_within_canvas(pos: %s) -> %s" % [pos, res])
	return res

func _draw_pixel(pos: Vector2, color: Color):
	print("_draw_pixel(pos: %s, color: %s, brush_size: %d)" % [pos, color, brush_size])
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
	if not current_image:
		return
		
	# Get all the points along the line between start and end
	var points = _get_line_points(start.floor(), end.floor())
	
	# Loop through each point on the line
	for point in points:
		var px = int(point.x)
		var py = int(point.y)
		
		# Check if the point is inside the canvas
		if px >= 0 and px < current_image.get_width() and py >= 0 and py < current_image.get_height():
			# For each brush offset, apply the brush around the point
			for offset in _brush_offsets:
				var x = px + offset.x
				var y = py + offset.y
				
				# Check bounds
				if x >= 0 and x < current_image.get_width() and y >= 0 and y < current_image.get_height():
					current_image.set_pixel(x, y, color)
	
	texture_update_pending = true

func _get_line_points(start: Vector2, end: Vector2) -> Array:
	#print("_get_line_points(start: %s, end: %s)" % [start, end])
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
	# === SCANLINE ALGORITHM === 
	# Get the color at the starting position
	var target_color = current_image.get_pixelv(pos)
	
	# If the target color is the same as the fill color, no need to do anything
	if target_color == current_color:
		return

	# Get image dimensions
	var img_width = current_image.get_width()
	var img_height = current_image.get_height()

	# Clamp the starting coordinates to valid image bounds
	var start_x = int(clamp(pos.x, 0, img_width - 1))
	var start_y = int(clamp(pos.y, 0, img_height - 1))
	
	# Initialize the queue with a horizontal segment on the starting row
	# Each queue item is [y, x_start, x_end]
	var queue = []
	queue.append([start_y, start_x, start_x])

	# Directions to check vertically (above and below)
	var directions = [-1, 1]
	
	# Continue processing while there are segments in the queue
	while not queue.is_empty():
		var segment = queue.pop_front()
		var y = segment[0]
		var x1 = segment[1]
		var x2 = segment[2]
		
		# Expand to the left from x1 as far as the color matches
		var left = x1
		while left >= 0 and current_image.get_pixel(left, y) == target_color:
			left -= 1
		left += 1  # Move back to the first valid pixel
		
		# Expand to the right from x2 as far as the color matches
		var right = x2
		while right < img_width and current_image.get_pixel(right, y) == target_color:
			right += 1
		right -= 1  # Move back to the last valid pixel
		
		# Fill the entire horizontal span with the new color
		for x in range(left, right + 1):
			current_image.set_pixel(x, y, current_color)
		
		# Check the rows above and below the current row
		for dy in directions:
			var ny = y + dy
			# Skip if out of bounds
			if ny < 0 or ny >= img_height:
				continue
				
			var nx = left
			while nx <= right:
				# If the color matches, we found a new span to fill
				if current_image.get_pixel(nx, ny) == target_color:
					var sx = nx
					# Move to the end of the matching segment
					while nx <= right and current_image.get_pixel(nx, ny) == target_color:
						nx += 1
					# Add the new span to the queue for future processing
					queue.append([ny, sx, nx - 1])
				else:
					nx += 1

	# Mark that the texture needs to be updated on screen
	texture_update_pending = true

func _draw_rect_shape(start: Vector2, end: Vector2):
	print("_draw_rect_shape(start: %s, end: %s)" % [start, end])
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
	print("_draw_circle_shape(center: %s, radius: %.1f)" % [center, radius])
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
	#print("_on_canvas_gui_input(event: %s)" % event)
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
		if not current_image:
			return
			
		var canvas_pos = _get_canvas_position(event.position)

		# Handle pencil and eraser tools
		if current_tool == TOOLS.PENCIL or current_tool == TOOLS.ERASER:
			is_drawing = event.pressed
			last_position = canvas_pos

			if event.pressed:
				# For single clicks, draw directly
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
		
		elif current_tool == TOOLS.EYE_DROPPER and event.pressed:
			_handle_eyedropper(canvas_pos)
			get_viewport().set_input_as_handled()
			return # Early exit avoids to update texture

		texture_update_pending = true  # Mark canvas for redraw

	# Continuous drawing while moving mouse
	elif event is InputEventMouseMotion and is_drawing:
		if not current_image:
			return
			
		var current_pos = _get_canvas_position(event.position)

		# Use point interpolation for smooth drawing
		if current_tool in [TOOLS.PENCIL, TOOLS.ERASER]:
			# Only draw if we've moved at least 1 pixel in canvas space
			if current_pos.distance_to(last_position) >= 1.0:
				_draw_line(last_position, current_pos, current_color if current_tool == TOOLS.PENCIL else Color.TRANSPARENT)
				last_position = current_pos

		texture_update_pending = true

	# Instead, rely solely on the cooldown in _process()
	texture_update_pending = true  # Mark for deferred update
	get_viewport().set_input_as_handled()

# Convert screen coordinates to zoomed canvas coordinates
func _get_canvas_position(screen_pos: Vector2) -> Vector2:
	# Get mouse position relative to scroll container
	var viewport_pos = scroll_container.get_local_mouse_position()
	
	# Convert to canvas coordinates (zoomed image space)
	var canvas_pos = (viewport_pos + Vector2(scroll_container.scroll_horizontal, scroll_container.scroll_vertical)) / zoom_level
	
	# Clamp to avoid out-of-bounds
	if current_image:
		canvas_pos.x = clamp(canvas_pos.x, 0, current_image.get_width() - 1)
		canvas_pos.y = clamp(canvas_pos.y, 0, current_image.get_height() - 1)
	return canvas_pos

# Draw a single pixel with smoothing (anti-aliasing)
func _draw_pixel_smooth(pos: Vector2, color: Color):
	# If there are no brush offsets, do nothing
	if _brush_offsets.is_empty():
		return
	
	# Get the width and height of the current image
	var img_width = current_image.get_width()
	var img_height = current_image.get_height()
	# Round the given position to the nearest integer pixel coordinates
	var center = Vector2i(pos)
	
	# Lock the image for batch updates (improves performance)
	#current_image.lock()
	
	# Loop through each offset in the brush
	for offset in _brush_offsets:
		# Calculate the actual pixel position
		var px = center.x + offset.x
		var py = center.y + offset.y
		
		# Check if the pixel is within the image bounds
		if px >= 0 and px < img_width and py >= 0 and py < img_height:
			# Calculate the distance from the center for smooth fading
			var distance = Vector2(offset.x, offset.y).length()
			# Compute the blending weight based on distance
			var weight = 1.0 - (distance / (brush_size / 2.0))
			# Clamp the weight between 0 and 1
			weight = clamp(weight, 0.0, 1.0)
			
			# Get the existing color at this pixel
			var existing_color = current_image.get_pixel(px, py)
			# Blend the existing color with the new color based on the weight
			current_image.set_pixel(px, py, existing_color.lerp(color, weight))
	
	# Unlock the image after all updates are done
	#current_image.unlock()
	# Mark the texture to be updated later
	texture_update_pending = true

# Finalize drawing of shapes (rectangle or circle)
func _finalize_shape(end_pos: Vector2):
	print("_finalize_shape(end_pos: %s, tool: %s)" % [end_pos, TOOLS.keys()[current_tool]])
	match current_tool:
		TOOLS.RECTANGLE:
			_draw_rect_shape(shape_start_pos, end_pos)
		TOOLS.CIRCLE:
			var radius = shape_start_pos.distance_to(end_pos)
			_draw_circle_shape(shape_start_pos, radius)
	texture_update_pending = true  # Mark for deferred update


func _on_tool_selected(tool: TOOLS):
	print("_on_tool_selected(tool: %s)" % TOOLS.keys()[tool])
	current_tool = tool
	_reset_drawing_state()

func _on_color_changed(color: Color):
	print("_on_color_changed(color: %s)" % color)
	current_color = color

func _on_brush_size_changed(value: float):
	print("_on_brush_size_changed(value: %.1f)" % value)
	brush_size_label.text = "%d" % value
	brush_size = value
	_precompute_brush_offsets() # Recompute when brush size changes

func _on_new_dialog_confirmed(width: int, height: int):
	print("_on_new_dialog_confirmed(width: %d, height: %d)" % [width, height])
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
	print("_on_OpenDialog_file_selected(path: %s)" % path)
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
	print("_on_SaveDialog_file_selected(path: %s)" % path)
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

func _on_eyedropper_pressed():
	current_tool = TOOLS.EYE_DROPPER
	_reset_drawing_state()
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)

func _handle_eyedropper(pos: Vector2):
	if current_image:
		current_color = current_image.get_pixelv(pos)
		color_picker.color = current_color
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func _reset_drawing_state():
	print("Resetting drawing state")
	is_drawing = false
	last_position = Vector2.ZERO
	shape_start_pos = Vector2.ZERO

func _precompute_brush_offsets():
	_brush_offsets.clear()
	var radius = brush_size / 2.0
	var radius_sq = radius * radius
	for x in range(brush_size):
		for y in range(brush_size):
			var dx = x - radius
			var dy = y - radius
			if Vector2(dx, dy).length_squared() <= radius_sq:
				_brush_offsets.append(Vector2i(dx, dy))

func _on_settings_pressed():
	# Set initial values before showing dialog
	settings_dialog.set_initial_values(zoom_sensitivity, panning_sensitivity, current_theme)
	settings_dialog.popup_centered()

func _on_theme_selected(theme_name):
	current_theme = theme_name
	_apply_theme(theme_name)

func _on_zoom_sensitivity_changed(value):
	zoom_sensitivity = value

func _on_panning_sensitivity_changed(value):
	panning_sensitivity = value

func _apply_theme(theme_name):
	var bg_color: Color
	match theme_name:
		"Dark":
			bg_color = Color(0.15, 0.15, 0.15)
		"Light":
			bg_color = Color(0.85, 0.85, 0.85)
		"Blue":
			bg_color = Color(0.1, 0.2, 0.3)
	
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = bg_color
	scroll_container.add_theme_stylebox_override("panel", bg_style)
	_setup_theme() # Volver a aplicar estilos de UI

func _process(delta):
	if texture_update_pending:
		update_cooldown += delta
		# Throttle to 30 FPS for heavy operations
		if update_cooldown >= 1.0 / 30.0:
			_update_texture()
			texture_update_pending = false
			update_cooldown = 0.0

func _exit_tree():
	print("_exit_tree()")
	
	if is_queued_for_deletion():
		return
		
	if canvas_drawing and is_instance_valid(canvas_drawing) and canvas_drawing.is_inside_tree():
		canvas_drawing.queue_free()
		canvas_drawing = null
