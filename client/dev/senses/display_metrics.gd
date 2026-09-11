extends RefCounted

const LIMIT := 256
var delays: Array[float] = []
var gaps: Array[float] = []
var displays := 0
var clock_errors := 0
var last_display_us := 0
var last_key := ""


func presented(key: String, delivery_unix_us: int) -> void:
	if key == last_key or delivery_unix_us <= 0: return
	last_key = key
	var now := Time.get_ticks_usec()
	var delay := (Time.get_unix_time_from_system() * 1000000.0 - delivery_unix_us) / 1000.0
	if delay < 0:
		clock_errors += 1
		return
	_append(delays, delay)
	if last_display_us > 0: _append(gaps, (now - last_display_us) / 1000.0)
	last_display_us = now
	displays += 1


func _append(values: Array[float], value: float) -> void:
	if values.size() == LIMIT: values.pop_front()
	values.append(value)


func summary() -> Dictionary:
	return {"displays": displays, "retained": delays.size(), "clock_errors": clock_errors,
		"delivery_ms": _distribution(delays), "update_gap_ms": _distribution(gaps)}


func _distribution(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {"p50": 0.0, "p95": 0.0, "max": 0.0}
	var sorted := values.duplicate()
	sorted.sort()
	return {"p50": sorted[ceili(sorted.size() * 0.5) - 1], "p95": sorted[ceili(sorted.size() * 0.95) - 1], "max": sorted.back()}
