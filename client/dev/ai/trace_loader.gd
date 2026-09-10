extends RefCounted

const Reader = preload("res://dev/ai/trace_reader.gd")
var _thread := Thread.new()
var _mutex := Mutex.new()
var _wake := Semaphore.new()
var _request: Dictionary = {}
var _result: Dictionary = {}
var _busy := false
var _stopping := false

func start() -> void:
	_thread.start(_run)

func request(kind: String, path: String, run_id: String, fingerprint: String, observer: int, revision := 0) -> bool:
	_mutex.lock()
	if _busy or _stopping:
		_mutex.unlock()
		return false
	_busy = true
	_request = {"kind": kind, "path": path, "run_id": run_id, "fingerprint": fingerprint, "observer": observer, "revision": revision}
	_mutex.unlock()
	_wake.post()
	return true

func take_result() -> Dictionary:
	_mutex.lock()
	var result := _result
	_result = {}
	if not result.is_empty(): _busy = false
	_mutex.unlock()
	return result

func close() -> void:
	if not _thread.is_started(): return
	_mutex.lock()
	_stopping = true
	_mutex.unlock()
	_wake.post()
	_thread.wait_to_finish()

func _run() -> void:
	# Only this thread owns the parser and its mutable history. Published record
	# dictionaries are immutable thereafter. No worker touches a scene-tree node.
	var live := Reader.new()
	while true:
		_wake.wait()
		_mutex.lock()
		var stop := _stopping
		var job := _request
		_request = {}
		_mutex.unlock()
		if stop: return
		var started := Time.get_ticks_usec()
		var source = live if job.kind == "snapshot" else Reader.new()
		var previous: int = source.last_sequence
		var changed: bool
		if job.kind == "snapshot":
			changed = source.read_snapshot(job.path, job.run_id, job.fingerprint, job.observer)
		else:
			changed = source.load_journal(job.path, job.fingerprint, job.observer)
		var batch: Array[Dictionary] = []
		if changed:
			for record: Dictionary in source.records:
				if int(record.sequence) > previous: batch.append(record)
		# Do not transfer the 128-record snapshot again. Destroy duplicated parsed
		# history on this worker, and give the UI only new immutable records.
		var metadata: Dictionary = source.snapshot.duplicate()
		metadata.erase("records")
		var result := {"kind": job.kind, "revision": job.revision, "records": batch, "snapshot": metadata,
			"last_sequence": source.last_sequence, "missed_live_records": source.missed_live_records,
			"error": source.error, "warning": source.warning, "changed": changed,
			"read_us": Time.get_ticks_usec() - started, "path": job.path}
		_mutex.lock()
		_result = result
		_mutex.unlock()

