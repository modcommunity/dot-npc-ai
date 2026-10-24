class_name DotNpcAiCrowdGrid
extends RefCounted

## A crowd's positions in a flat spatial hash, rebuilt once a tick, so spacing and "who is near"
## cost a few cells rather than a walk over everybody or an array built per question.
##
## Cells are linked lists in packed arrays (a head per cell, a next per entry): a rebuild
## allocates nothing once the arrays have grown, and a query allocates nothing at all.

## The cell's side in metres; a query reaches every cell its radius touches.
var cell: float = 2.0

var _pos := PackedVector3Array()
var _ids := PackedInt64Array()
var _next := PackedInt32Array()
var _head: Dictionary = {}
var _index: Dictionary = {}
var _count: int = 0


func _init(p_cell: float = 2.0) -> void:
	cell = maxf(p_cell, 0.1)


## Empties the grid, keeping its arrays for the next fill.
func clear() -> void:
	_head.clear()
	_index.clear()
	_count = 0


## Adds [param id] standing at [param at]; returns its index for the tick.
func add(id: int, at: Vector3) -> int:
	if _count >= _pos.size():
		var grow := maxi(16, _pos.size())
		_pos.resize(_pos.size() + grow)
		_ids.resize(_ids.size() + grow)
		_next.resize(_next.size() + grow)

	var i := _count
	_count += 1
	_pos[i] = at
	_ids[i] = id
	var key := _key(floori(at.x / cell), floori(at.z / cell))
	_next[i] = int(_head.get(key, -1))
	_head[key] = i
	_index[id] = i
	return i


func size() -> int:
	return _count


func has(id: int) -> bool:
	return _index.has(id)


## The index [param id] was added under this tick, or -1.
func index_of(id: int) -> int:
	return int(_index.get(id, -1))


func position_of(index: int) -> Vector3:
	return _pos[index]


func id_of(index: int) -> int:
	return _ids[index]


## Indices within [param radius] of [param point] in 3D, appended to [param out] (cleared first).
func near(point: Vector3, radius: float, out: PackedInt32Array) -> PackedInt32Array:
	out.clear()
	var reach := radius * radius
	var x1 := floori((point.x + radius) / cell)
	var z0 := floori((point.z - radius) / cell)
	var z1 := floori((point.z + radius) / cell)

	for cx in range(floori((point.x - radius) / cell), x1 + 1):
		for cz in range(z0, z1 + 1):
			var i := int(_head.get(_key(cx, cz), -1))
			while i >= 0:
				if _pos[i].distance_squared_to(point) <= reach:
					out.append(i)
				i = _next[i]

	return out


## [method DotNpcAiSteering.separate] over the crowd round entry [param self_index], with no
## array built: neighbours are those within [param query] metres of where it was added (the
## broad phase a caller of `separate` would have asked for), pushed from [param from].
func separation(self_index: int, from: Vector3, radius: float, query: float, tie_break: Vector3) -> Vector3:
	if radius <= 0.0 or self_index < 0:
		return Vector3.ZERO

	var escape := Vector3(tie_break.x, 0.0, tie_break.z)
	escape = escape.normalized() if escape.length() > 0.001 else Vector3.ZERO
	var centre := _pos[self_index]
	var reach := query * query
	var tall := radius * 2.0
	var push := Vector3.ZERO
	var x1 := floori((centre.x + query) / cell)
	var z0 := floori((centre.z - query) / cell)
	var z1 := floori((centre.z + query) / cell)

	for cx in range(floori((centre.x - query) / cell), x1 + 1):
		for cz in range(z0, z1 + 1):
			var i := int(_head.get(_key(cx, cz), -1))
			while i >= 0:
				var other := _pos[i]
				if i != self_index and other.distance_squared_to(centre) <= reach:
					var dx := from.x - other.x
					var dz := from.z - other.z
					var distance := sqrt(dx * dx + dz * dz)
					if distance <= radius and absf(from.y - other.y) <= tall:
						if distance < 0.05:
							push += escape
						else:
							push += Vector3(dx, 0.0, dz) / distance * (1.0 - distance / radius)
				i = _next[i]

	return push.normalized() if push.length() > 0.001 else Vector3.ZERO


func describe() -> Dictionary:
	return {"entries": _count, "cells": _head.size(), "cell": cell}


static func _key(cx: int, cz: int) -> int:
	return (cx << 32) ^ (cz & 0xFFFFFFFF)
