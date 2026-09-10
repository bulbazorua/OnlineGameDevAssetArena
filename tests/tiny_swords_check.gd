extends "./host_check.gd"

const AssetScale = preload("res://presentation/asset_scale.gd")


func _host_arguments() -> PackedStringArray:
	var arguments := super._host_arguments()
	arguments.append_array(["--dev", "--dev-p1=triangle", "--dev-p2=diamond", "--dev-arena=tiny_swords_village"])
	return arguments


func _check() -> String:
	var first = _new_client()
	if not await _wait_for(func(): return first.network.session != null): return "P1 could not connect."
	var second = _new_client()
	var audience = _new_client(true)
	if not await _wait_for(func(): return audience.network.session != null and audience.network.session.phase == SessionSnapshot.Phase.IN_ARENA): return "Tiny Swords arena did not start."
	for client in clients:
		var world = client.game_arena.world
		if world.definition.id != 4 or world.props.size() != 12: return "Tiny Swords buildings were not present in every client."
		if world.terrain_layer.tile_set.tile_size != Vector2i(64, 64) or world.terrain_layer.scale != Vector2(0.5, 0.5): return "64px tiles do not map to the 32-unit grid."
		if world.props[0].texture.get_size() * world.props[0].scale != Vector2(160, 128): return "Castle does not occupy its authored five-cell facade width."
		if not world.y_sort_enabled or not client.game_arena.y_sort_enabled or not client.game_arena.get_node("Characters").y_sort_enabled: return "Buildings and characters do not share ground-position sorting."
	# Independent source resolutions produce the same transformed sprite bounds.
	for size in [1.0, 1.5]:
		for pixels in [16, 32]:
			var image := Image.create(pixels, pixels, false, Image.FORMAT_RGBA8)
			image.fill(Color.WHITE)
			var sprite := Sprite2D.new()
			sprite.texture = ImageTexture.create_from_image(image)
			sprite.scale = Vector2.ONE * AssetScale.factor(pixels, size)
			var bounds := sprite.transform * sprite.get_rect()
			if not bounds.size.is_equal_approx(Vector2.ONE * 32 * size): return "Resolution-independent sizing produced different world bounds."
			sprite.free()
	# Both fighters approach different castles. Collision is enforced by Odin
	# from the shared building terrain, with matching prediction on every client.
	_key(first, KEY_A, true)
	_key(second, KEY_D, true)
	if not await _wait_for(func(): return _position(first, 0).x <= 290): return "P1 did not approach the west castle."
	_key(first, KEY_A, false)
	if not await _wait_for(func(): return _position(second, 1).x >= 1630): return "P2 did not approach the east castle."
	_key(second, KEY_D, false)
	await create_timer(0.15).timeout
	_key(first, KEY_W, true)
	_key(second, KEY_W, true)
	await create_timer(1.2).timeout
	_key(first, KEY_W, false)
	_key(second, KEY_W, false)
	await create_timer(0.2).timeout
	for client in clients:
		for index in 2:
			var position := _position(client, index)
			if position.y < 332 or position.y > 335: return "A fighter crossed a castle footprint or was blocked too early."
			if position.distance_to(_position(first, index)) > 0.01: return "Building collision did not converge across the audience/players."
			var state = client.network.session.characters[index]
			if client.game_arena.character_views[state.entity_id].position.distance_to(position) > 1: return "Rendered building collision disagrees with the host."
	first.network.request_return_to_lobby()
	if not await _wait_for(func(): return first.lobby.visible): return "Could not return to lobby."
	first.network.request_start_selection()
	if not await _wait_for(func(): return audience.network.session.phase == SessionSnapshot.Phase.SELECTING): return "Could not return to selection."
	first.network.request_arena(4)
	if not await _wait_for(func(): return audience.network.session.map_id == 4): return "Village selection was not shared."
	if not audience.arena_selection.cards.has(4) or audience.arena_selection.preview.world.props.size() != 12: return "Village was absent from selection/preview."
	first.network.request_arena(1)
	if not await _wait_for(func(): return audience.network.session.map_id == 1): return "Could not switch to an existing arena."
	var preview = audience.arena_selection.preview.world
	if not preview.props.is_empty() or preview.terrain_layer.scale != Vector2(2, 2): return "Switching themes retained buildings or the wrong native tile scale."
	return ""


func _position(client: Node, index: int) -> Vector2:
	return client.network.session.characters[index].position


func _key(client: Node, key: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = pressed
	client.game_arena._unhandled_key_input(event)
