class_name ShipBakeSession
extends RefCounted
## The engine bake as a session (ADR 0030), lifted out of ShipBuilder: the last bake, whether the
## document has moved on since, one engine job at a time with at most one update queued behind
## it, and the exploded view's extras made from the last bake the first time they are asked for.
##
## The builder keeps what is ON SCREEN - baked or preview, exploded or assembled, rooms whole or
## in pieces. This keeps what the engine has MADE. It reads the document through a callable
## rather than holding one, so a bake of a document since replaced is recognised and thrown away
## (ADR 0028), and it tells the builder a bake or its extras landed through another.
##
## Never automatic (ADR 0028, the author's rule): nothing here starts a bake on its own. The
## builder asks - UPDATE MESHES, a ship arriving, EXPLODE or ROOMS: WHOLE wanting their extras.

## The last engine bake, its extras merged in once made; {} before the first.
var last: Dictionary = {}
## The document has changed since [member last] was made.
var stale: bool = false
## A bake or an extras pass is in the engine now. The visual checks wait on it.
var busy: bool = false

var _pending: bool = false
var _host: Node = null
var _doc_of: Callable = Callable()
var _landed: Callable = Callable()
var _progress: Callable = Callable()
var _data: ShipData = null
var _config: ShipConfig = null


## [param host] holds the engine's nodes while they compute; [param doc_of] returns the document
## as it is now; [param landed] is called whenever [member last] changes; [param progress] gets
## every pass's (fraction, label).
func _init(host: Node, doc_of: Callable, landed: Callable, progress: Callable) -> void:
	_host = host
	_doc_of = doc_of
	_landed = landed
	_progress = progress


## Bake the document as it is now. A request while the engine is busy queues one more, and a
## bake of a document that was replaced meanwhile is discarded for a bake of the new one.
func request_update(data: ShipData, cfg: ShipConfig) -> void:
	_data = data
	_config = cfg
	var doc: ShipDoc = _doc_of.call()
	if doc == null or _host == null:
		return
	if busy:
		_pending = true
		return
	busy = true
	_pending = false
	stale = false
	var made: Dictionary = await ShipCsgBake.bake(_host, doc, data, cfg, _progress)
	busy = false
	if _doc_of.call() != doc:
		# Another document arrived meanwhile (measured: the chooser's blank ship baking when the
		# class replaced it): its bake is not this ship's. Bake this one instead.
		request_update(data, cfg)
		return
	if _pending:
		stale = true
	last = made
	_landed.call()
	if _pending:
		request_update(data, cfg)


## Whether [member last] carries its extras - or has had them attempted, which is the same answer
## to "should they be asked for again".
func has_extras() -> bool:
	return bool(last.get(ShipCsgBake.EXTRAS_READY, false))


## Make the halves and whole rooms of [member last], once. Does nothing while the engine is busy:
## whatever it is busy with lands through [code]landed[/code], and the builder asks again then.
func request_extras() -> void:
	if busy or last.is_empty() or has_extras():
		return
	busy = true
	var from: Dictionary = last
	var made: Dictionary = await ShipCsgBake.bake_extras(_host, from, _progress)
	busy = false
	# An update that landed meanwhile replaced the bake these belong to.
	if is_same(last, from):
		last = made
		_landed.call()
	if _pending:
		request_update(_data, _config)


## Forget the bake: the document was swapped wholesale.
func drop() -> void:
	last = {}
	stale = false
