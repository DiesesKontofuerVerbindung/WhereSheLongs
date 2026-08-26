class_name WebsocketBlinkDetector
extends Node

signal blink(payload: Dictionary)
signal frame(payload: Dictionary)
signal connection_changed(connected: bool)

var url: String = "ws://127.0.0.1:8765"
var connected: bool = false
var _peer: WebSocketPeer = WebSocketPeer.new()


func start(p_url: String) -> void:
	url = p_url
	var err := _peer.connect_to_url(url)
	if err != OK:
		push_warning("Blink detector WS connect failed: %s" % err)


func _process(_delta: float) -> void:
	_peer.poll()
	var state := _peer.get_ready_state()
	var now_connected := state == WebSocketPeer.STATE_OPEN
	if now_connected != connected:
		connected = now_connected
		connection_changed.emit(connected)
	if state != WebSocketPeer.STATE_OPEN:
		return
	while _peer.get_available_packet_count() > 0:
		var packet := _peer.get_packet()
		var text := packet.get_string_from_utf8()
		var data: Variant = JSON.parse_string(text)
		if typeof(data) != TYPE_DICTIONARY:
			continue
		var msg: Dictionary = data
		var kind := str(msg.get("type", ""))
		if kind == "blink":
			blink.emit(msg)
		elif kind == "frame" or kind == "hello":
			frame.emit(msg)
