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
enum TOOLS {PENCIL, ERASER, FILL, RECTANGLE, CIRCLE}
var current_tool := TOOLS.PENCIL
var current_color := Color.BLACK
var brush_size := 1
var zoom_level := 1.0
var is_drawing := false
var last_position := Vector2.ZERO
var shape_start_pos := Vector2.ZERO
var current_image: Image
var current_texture: ImageTexture
var current_path := ""
var canvas_drawing: CanvasDrawing 

@onready var scroll_container: ScrollContainer = $VBoxContainer/ScrollContainer
@onready var canvas: TextureRect = $VBoxContainer/ScrollContainer/Canvas
@onready var tools_container: HBoxContainer = $VBoxContainer/Toolbar/ToolsContainer
@onready var color_picker: ColorPickerButton = $VBoxContainer/Toolbar/ColorPickerButton
@onready var brush_size_slider: Slider = $VBoxContainer/Toolbar/HBoxContainer/HSlider
@onready var save_dialog: FileDialog = $SaveDialog
@onready var open_dialog: FileDialog = $OpenDialog

func _ready():
	self.visible = true
	
	# Remove existing CanvasDrawing node if it exists
	for child in scroll_container.get_children():
		if child is CanvasDrawing:
			child.queue_free()
			 
	# Visualize the canvas area
	var style = StyleBoxFlat.new()
	style.bg_color = Color(1, 0, 0)  # red
	canvas.add_theme_stylebox_override("panel", style)
	
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.15, 0.15, 0.15)  # grey
	scroll_container.add_theme_stylebox_override("panel", bg_style)
	
	canvas_drawing = CanvasDrawing.new(self)
	scroll_container.add_child(canvas_drawing)
	scroll_container.move_child(canvas_drawing, 0)
	
	_setup_theme()
	_setup_tools()
	new_image(64, 64)
	_update_zoom()
	
	color_picker.color_changed.connect(_on_color_changed)
	brush_size_slider.value_changed.connect(_on_brush_size_changed)
	$VBoxContainer/Toolbar/New.pressed.connect(_on_NewButton_pressed)
	$VBoxContainer/Toolbar/Open.pressed.connect(_on_OpenButton_pressed)
	$VBoxContainer/Toolbar/Save.pressed.connect(_on_SaveButton_pressed)

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

func _setup_tools():
	var tools = {
		"Pencil": TOOLS.PENCIL,
		"Eraser": TOOLS.ERASER,
		"Fill": TOOLS.FILL,
		"Rectangle": TOOLS.RECTANGLE,
		"Circle": TOOLS.CIRCLE
	}
	
	for tool_name in tools:
		var btn = Button.new()
		btn.text = tool_name
		btn.toggle_mode = true
		btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		btn.connect("pressed", _on_tool_selected.bind(tools[tool_name]))
		tools_container.add_child(btn)

func new_image(width: int, height: int):
	current_image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	current_image.fill(Color(1, 0, 0, 1))  # Red for visibility
	
	# Reset zoom and texture
	zoom_level = 1.0
	_update_texture()
	
	# Wait for UI to update
	await get_tree().process_frame
	
	# Force reset scroll to top-left
	scroll_container.scroll_horizontal = 0
	scroll_container.scroll_vertical = 0
	print("New image created. Scroll reset to (0, 0)")

func load_texture(texture: ImageTexture):
	current_texture = texture
	current_image = current_texture.get_image()
	_update_texture()

func _update_texture():
	if current_image:
		# DEBUG: Print image data
		print("Updating texture. Image format: ", current_image.get_format(), " | Size: ", current_image.get_size())
		
		# Force create a NEW texture
		current_texture = ImageTexture.create_from_image(current_image)
		canvas.texture = current_texture
		
		# DEBUG: Force redraw
		canvas.queue_redraw()
		print("Texture updated: ", current_texture)

func _update_zoom():
	if current_image:
		var img_size = current_image.get_size()
		var scaled_size = img_size * zoom_level
		
		# Set canvas size to match zoom
		canvas.custom_minimum_size = scaled_size
		canvas.size = scaled_size
		
		# Force ScrollContainer to match the canvas size
		scroll_container.custom_minimum_size = scaled_size
		scroll_container.queue_redraw()
		
		print("Zoom updated. Canvas size: ", canvas.size)

func _get_canvas_position(screen_pos: Vector2) -> Vector2:
	var scroll_offset = Vector2(scroll_container.scroll_horizontal, scroll_container.scroll_vertical)
	return (screen_pos - scroll_container.position + scroll_offset - canvas.position) / zoom_level

func _is_within_canvas(pos: Vector2) -> bool:
	return pos.x >= 0 && pos.x < current_image.get_width() && pos.y >= 0 && pos.y < current_image.get_height()

func _draw_pixel(pos: Vector2, color: Color):
	current_image.lock()
	for x in range(brush_size):
		for y in range(brush_size):
			var px = pos.x - brush_size/2 + x
			var py = pos.y - brush_size/2 + y
			if _is_within_canvas(Vector2(px, py)):
				current_image.set_pixel(px, py, color)
	current_image.unlock()

func _draw_line(start: Vector2, end: Vector2, color: Color):
	var points = _get_line_points(start, end)
	for point in points:
		_draw_pixel(point, color)
	_update_texture()

func _get_line_points(start: Vector2, end: Vector2) -> Array:
	var points = []
	var dx = absi(end.x - start.x)
	var dy = -absi(end.y - start.y)
	var sx = 1 if start.x < end.x else -1
	var sy = 1 if start.y < end.y else -1
	var err = dx + dy
	
	var x = start.x
	var y = start.y
	
	while true:
		points.append(Vector2(x, y))
		if x == end.x && y == end.y:
			break
		var e2 = 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy
	return points

func _flood_fill(pos: Vector2):
	var target_color = current_image.get_pixelv(pos)
	if target_color == current_color:
		return
	
	var queue = [pos]
	current_image.lock()
	
	while not queue.is_empty():
		var p = queue.pop_front()
		if _is_within_canvas(p) && current_image.get_pixelv(p) == target_color:
			current_image.set_pixelv(p, current_color)
			queue.append(Vector2(p.x + 1, p.y))
			queue.append(Vector2(p.x - 1, p.y))
			queue.append(Vector2(p.x, p.y + 1))
			queue.append(Vector2(p.x, p.y - 1))
	
	current_image.unlock()
	_update_texture()

func _draw_rect_shape(start: Vector2, end: Vector2):
	current_image.lock()
	var rect = Rect2i(start, end - start).abs()
	for x in rect.size.x:
		for y in rect.size.y:
			var pos = Vector2(rect.position.x + x, rect.position.y + y)
			if _is_within_canvas(pos):
				current_image.set_pixelv(pos, current_color)
	current_image.unlock()

func _draw_circle_shape(center: Vector2, radius: float):
	current_image.lock()
	var radius_sq = pow(radius, 2)
	for x in range(center.x - radius, center.x + radius):
		for y in range(center.y - radius, center.y + radius):
			var pos = Vector2(x, y)
			if _is_within_canvas(pos) && pos.distance_squared_to(center) <= radius_sq:
				current_image.set_pixelv(pos, current_color)
	current_image.unlock()

func _on_Canvas_gui_input(event):
	# Handle mouse wheel for zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_level = clamp(zoom_level * 1.1, 0.1, 8.0)
			_update_zoom()
			get_viewport().set_input_as_handled()  # Block default scrolling
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_level = clamp(zoom_level / 1.1, 0.1, 8.0)
			_update_zoom()
			get_viewport().set_input_as_handled()

func _on_tool_selected(tool: TOOLS):
	current_tool = tool

func _on_color_changed(color: Color):
	current_color = color

func _on_brush_size_changed(value: float):
	brush_size = clampi(int(value), 1, 32)

func _on_NewButton_pressed():
	print("New button pressed")
	new_image(512, 512)
	# Force focus to show hover state
	await get_tree().process_frame
	$VBoxContainer/Toolbar/New.grab_focus()

func _on_OpenButton_pressed():
	print("Open button pressed")
	open_dialog.popup_centered()

func _on_SaveButton_pressed():
	print("Save button pressed")
	save_dialog.popup_centered()

func _on_SaveDialog_file_selected(path: String):
	current_image.save_png(path)
	_notify_resource_update(path)

func _on_OpenDialog_file_selected(path: String):
	current_image = Image.load_from_file(path)
	_update_texture()
	_notify_resource_update(path)

func _notify_resource_update(path: String):
	EditorInterface.get_resource_filesystem().scan()
	EditorInterface.get_resource_filesystem().scan_sources()
	if ResourceLoader.exists(path):
		EditorInterface.edit_resource(load(path))

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_F:
		await get_tree().process_frame
		
		# Get viewport and canvas sizes
		var viewport_size = scroll_container.size
		var canvas_size = canvas.size
		
		# Calculate centered scroll
		var target_h = max(0, (canvas_size.x - viewport_size.x) / 2)
		var target_v = max(0, (canvas_size.y - viewport_size.y) / 2)
		
		# Apply scroll
		scroll_container.scroll_horizontal = target_h
		scroll_container.scroll_vertical = target_v
		print("Centered at: ", Vector2(target_h, target_v))

func _exit_tree():
	# Cleanup CanvasDrawing node
	if canvas_drawing and is_instance_valid(canvas_drawing):
		canvas_drawing.queue_free()
