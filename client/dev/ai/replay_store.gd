extends RefCounted

const Reader = preload("res://dev/ai/replay_reader.gd")
var _thread := Thread.new()
var _mutex := Mutex.new()
var _wake := Semaphore.new()
var _job: Dictionary = {}
var _result: Dictionary = {}
var _stop := false
var _progress := 0.0

func open(path: String, fingerprint: String) -> void:
	_thread.start(_run.bind(path, fingerprint))

func close() -> void:
	if not _thread.is_started(): return
	_mutex.lock()
	_stop = true
	_mutex.unlock()
	_wake.post()
	_thread.wait_to_finish()

func request_frame(index: int, token: int) -> void:
	_mutex.lock()
	var notify := _job.is_empty()
	_job = {"index": index, "token": token}
	_mutex.unlock()
	if notify: _wake.post()

func take_result() -> Dictionary:
	_mutex.lock()
	var result := _result
	_result = {}
	if result.is_empty(): result = {"kind": "progress", "value": _progress}
	_mutex.unlock()
	return result

func _cancelled() -> bool:
	_mutex.lock()
	var stop := _stop
	_mutex.unlock()
	return stop

func _set_progress(value: float) -> void:
	_mutex.lock()
	_progress = value
	_mutex.unlock()

func _publish(result: Dictionary) -> void:
	_mutex.lock()
	_result = result
	_mutex.unlock()

func _run(path: String, fingerprint: String) -> void:
	var reader := Reader.new()
	var loaded := reader.scan(path, fingerprint, _set_progress, _cancelled)
	if _cancelled(): return
	_publish({"kind": "index", "error": reader.error, "warning": reader.warning, "header": reader.header, "entries": reader.entries})
	if not loaded: return
	while true:
		_wake.wait()
		if _cancelled(): return
		_mutex.lock()
		var job := _job
		_job = {}
		_mutex.unlock()
		if job.is_empty(): continue
		var result := reader.read_frame(int(job.index))
		result["kind"] = "frame"
		result["index"] = job.index
		result["token"] = job.token
		_publish(result)

