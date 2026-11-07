class_name DotNpcAiNavHandLinks
extends RefCounted

## Links a person placed by hand (a ladder, a door, a jump, a drop), as data: the `nav_links` section of a map's data bundle.
## [b]Kept apart from [DotNpcAiNavAnnotations] on purpose:[/b] the annotator's links are a cache that a re-bake replaces, these are authored and must survive it. [method apply_to] copies them into an annotations object (kind and ends as the annotator's own, so any pathing reads both the same way).
## Ids are stable and never reused within one set, so a tool can name a link across edits.

# No log channel: a container. The tool that edits it logs who changed what.

## Bumped when the section's layout changes.
const VERSION := 1

## `{"id": int, "from": Vector3, "to": Vector3, "kind": int, "cost": float, "flags": int}`, one way each, in the order added.
var links: Array[Dictionary] = []

var _next_id: int = 1


## Adds a link from [param from] to [param to] and returns its id, or 0 when it is refused: a kind below 0, or two ends within a centimetre of each other. [param kind] is a [constant DotNpcAiNavAnnotations.LINK_NAMES] key or a game's own (from [constant DotNpcAiNavAnnotations.LINK_GAME_FIRST]). [param two_way] adds the return link too (same cost; a drop is usually one way); the id returned is the forward link's.
func add(from: Vector3, to: Vector3, kind: int, cost: float = -1.0, flags: int = 0, two_way: bool = false) -> int:
	if kind < 0 or from.distance_to(to) < 0.01:
		return 0
	if cost < 0.0:
		cost = from.distance_to(to)
	var id := _next_id
	_next_id += 1
	links.append({"id": id, "from": from, "to": to, "kind": kind, "cost": cost, "flags": flags})
	if two_way:
		var back := _next_id
		_next_id += 1
		links.append({"id": back, "from": to, "to": from, "kind": kind, "cost": cost, "flags": flags})
	return id


## Removes the link [param id]. False when there is none.
func remove(id: int) -> bool:
	for i in links.size():
		if int(links[i]["id"]) == id:
			links.remove_at(i)
			return true
	return false


## The link [param id], or an empty dictionary.
func get_link(id: int) -> Dictionary:
	for link in links:
		if int(link["id"]) == id:
			return link
	return {}


## The id of the link nearest [param point] (measured to either end) within [param within] metres, or 0.
func nearest(point: Vector3, within: float = 2.0) -> int:
	var best := 0
	var best_d := within
	for link in links:
		var d := minf(point.distance_to(link["from"]), point.distance_to(link["to"]))
		if d <= best_d:
			best_d = d
			best = int(link["id"])
	return best


func clear() -> void:
	links.clear()


## Appends the links to [param into]'s [member DotNpcAiNavAnnotations.links] that are not already there (same ends and kind), and returns how many were added. Call it after every annotation run, since a run replaces the generated links.
func apply_to(into: DotNpcAiNavAnnotations) -> int:
	var added := 0
	for link in links:
		var present := false
		for have in into.links:
			if int(have["kind"]) == int(link["kind"]) and (have["from"] as Vector3).is_equal_approx(link["from"]) and (have["to"] as Vector3).is_equal_approx(link["to"]):
				present = true
				break
		if not present:
			into.links.append({"from": link["from"], "to": link["to"], "kind": link["kind"], "cost": link["cost"]})
			added += 1
	return added


func to_dict() -> Dictionary:
	var rows: Array = []
	for link in links:
		rows.append([int(link["id"]), _v(link["from"]), _v(link["to"]), int(link["kind"]), snappedf(float(link["cost"]), 0.001), int(link["flags"])])
	return {"version": VERSION, "next_id": _next_id, "links": rows}


## The set [method to_dict] wrote, or a failure for another [constant VERSION] or a malformed row (nothing is half-loaded).
static func from_dict(d: Dictionary) -> DotResult:
	if int(d.get("version", -1)) != VERSION:
		return DotResult.fail(DotError.CODE_VERSION, "nav links of version %s, this reads %d" % [str(d.get("version", "none")), VERSION])
	var out := DotNpcAiNavHandLinks.new()
	var top := 0
	for row: Variant in d.get("links", []):
		if not (row is Array) or (row as Array).size() < 6 or int(row[0]) <= 0:
			return DotResult.fail(DotError.CODE_PARSE, "a nav link row is malformed")
		var id := int(row[0])
		if out.get_link(id).size() > 0:
			return DotResult.fail(DotError.CODE_PARSE, "nav link id %d appears twice" % id)
		top = maxi(top, id)
		out.links.append({"id": id, "from": _p(row[1]), "to": _p(row[2]), "kind": int(row[3]), "cost": float(row[4]), "flags": int(row[5])})
	out._next_id = maxi(int(d.get("next_id", 1)), top + 1)
	return DotResult.success(out)


static func _v(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]


static func _p(a: Variant) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO
