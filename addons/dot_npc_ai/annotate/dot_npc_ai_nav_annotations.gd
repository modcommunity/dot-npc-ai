class_name DotNpcAiNavAnnotations
extends RefCounted

## What a map means to somebody walking it, worked out from its navigation mesh and its
## colliders: where a body can drop, jump up or jump across that the mesh does not join
## (links), where it can stand out of sight or behind something (spots), and the narrow
## places most routes go through (chokepoints).
##
## [b]Data only.[/b] [DotNpcAiNavAnnotator] fills it; this holds it, serialises it, and
## answers the few questions every consumer asks. It names no navigation class of any
## addon: points are [Vector3]s in the map's space, so dot-bot's mesh, dot-npc's graph and a
## game's own pathing read the same annotations.
##
## [b]Cached by [member key].[/b] The key is a digest of the mesh it was made from, the
## settings it was made with and [constant VERSION]; the same map baked the same way gets
## the same key on every machine, so [method save] and [method load_file] can keep one file
## per map and a server that changes to a map it has seen pays nothing.
##
## Spots are dictionaries compatible with dot-bot's hiding layer (`at`, `exposure`,
## `seen_by`), so a game hands [method hiding_spots] straight to its choose step.

# No log channel: a container. The annotator logs what it found.

## Bumped whenever the annotator would produce something different from the same input,
## so an old cache is a miss rather than a wrong answer.
const VERSION := 1

## A link's kind. A drop is walked off; a jump up and a jump across need the jump button.
## A ladder and anything else a game declares ([method DotNpcAiNavAnnotator.declare]) keep
## the kind they were given; [constant LINK_GAME_FIRST] and above are a game's own.
const LINK_DROP := 0
const LINK_JUMP_UP := 1
const LINK_JUMP_GAP := 2
const LINK_LADDER := 3
const LINK_TELEPORT := 4
const LINK_RIDE := 5
const LINK_GAME_FIRST := 16

const LINK_NAMES := {0: "drop", 1: "jump_up", 2: "jump_gap", 3: "ladder", 4: "teleport", 5: "ride"}

## Directions of [member spots]' cover masks: bit i is the horizontal direction at
## `i * TAU / COVER_DIRECTIONS` from +X toward +Z (the same turn as `Vector3.rotated(UP, -a)`
## is not; see [method direction]).
const COVER_DIRECTIONS := 8

## The digest this was made for (hex), empty when made by hand.
var key: String = ""

## `{"from": Vector3, "to": Vector3, "kind": int, "cost": float}`, one way each.
var links: Array[Dictionary] = []

## Every surveyed place beside a wall: `{"at": Vector3 (feet, on the mesh), "normal":
## Vector3 (away from the wall), "exposure": float 0..1 (share of the map's watchers that
## see a crouched head there), "seen_by": int, "enclosure": float 0..1 (share of directions
## blocked close by at a crouched head), "low": int (cover mask at a crouched head),
## "high": int (cover mask at a standing chest)}`.
var spots: Array[Dictionary] = []

## Indices into [member spots] of the hiding places: low exposure, enclosed, apart.
var hiding: PackedInt32Array = PackedInt32Array()

## `{"at": Vector3, "width": float (walkable metres across), "traffic": float (share of
## sampled routes that pass)}`.
var chokepoints: Array[Dictionary] = []

## What the annotator measured: timings and counts, for [method describe].
var stats: Dictionary = {}


## The unit vector of cover direction [param i] (see [constant COVER_DIRECTIONS]).
static func direction(i: int) -> Vector3:
	var a := float(i) * TAU / float(COVER_DIRECTIONS)
	return Vector3(cos(a), 0.0, sin(a))


## The cover direction nearest the horizontal of [param v].
static func direction_index(v: Vector3) -> int:
	var a := atan2(v.z, v.x)
	return posmod(roundi(a / (TAU / float(COVER_DIRECTIONS))), COVER_DIRECTIONS)


## The hiding places as spot dictionaries, best first.
func hiding_spots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in hiding:
		out.append(spots[i])
	return out


## Spots that hide a body at [param at_height] (`"low"` crouched or `"high"` standing) from
## [param threat], within [param within] metres of [param near]: the direction from the spot
## to the threat is one its mask blocks. Nearest first.
func cover_from(threat: Vector3, near: Vector3, within: float = 15.0, at_height: String = "low") -> Array[Dictionary]:
	var found: Array = []
	for spot in spots:
		var at: Vector3 = spot["at"]
		var d := at.distance_to(near)
		if d > within:
			continue
		var mask := int(spot.get(at_height, 0))
		if mask == 0:
			continue
		var to := threat - at
		to.y = 0.0
		if to.length() < 1.0:
			continue
		if mask & (1 << direction_index(to)):
			found.append([d, spot])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var out: Array[Dictionary] = []
	for pair: Array in found:
		out.append(pair[1])
	return out


## Links of [param kind] (-1 for all).
func links_of(kind: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for link in links:
		if kind < 0 or int(link["kind"]) == kind:
			out.append(link)
	return out


## How many links of each kind, by name.
func link_counts() -> Dictionary:
	var out := {}
	for link in links:
		var k := int(link["kind"])
		var label: String = LINK_NAMES.get(k, "game_%d" % k)
		out[label] = int(out.get(label, 0)) + 1
	return out


# --- Serialising ----------------------------------------------------------------

func to_dict() -> Dictionary:
	var l: Array = []
	for link in links:
		l.append([_v(link["from"]), _v(link["to"]), int(link["kind"]), snappedf(float(link.get("cost", 1.0)), 0.001)])
	var s: Array = []
	for spot in spots:
		s.append([_v(spot["at"]), _v(spot["normal"]), snappedf(float(spot["exposure"]), 0.001), int(spot["seen_by"]),
			snappedf(float(spot["enclosure"]), 0.001), int(spot["low"]), int(spot["high"])])
	var c: Array = []
	for choke in chokepoints:
		c.append([_v(choke["at"]), snappedf(float(choke["width"]), 0.01), snappedf(float(choke["traffic"]), 0.001)])
	return {"version": VERSION, "key": key, "links": l, "spots": s, "hiding": Array(hiding), "chokepoints": c, "stats": stats}


## The annotations [method to_dict] wrote, or a failure for a different [constant VERSION]
## or a malformed document.
static func from_dict(d: Dictionary) -> DotResult:
	if int(d.get("version", -1)) != VERSION:
		return DotResult.fail(DotError.CODE_VERSION, "annotations of version %s, this reads %d" % [str(d.get("version", "none")), VERSION])
	var out := DotNpcAiNavAnnotations.new()
	out.key = str(d.get("key", ""))
	for row: Variant in d.get("links", []):
		if not (row is Array) or (row as Array).size() < 4:
			return DotResult.fail(DotError.CODE_PARSE, "a link row is malformed")
		out.links.append({"from": _p(row[0]), "to": _p(row[1]), "kind": int(row[2]), "cost": float(row[3])})
	for row: Variant in d.get("spots", []):
		if not (row is Array) or (row as Array).size() < 7:
			return DotResult.fail(DotError.CODE_PARSE, "a spot row is malformed")
		out.spots.append({"at": _p(row[0]), "normal": _p(row[1]), "exposure": float(row[2]), "seen_by": int(row[3]),
			"enclosure": float(row[4]), "low": int(row[5]), "high": int(row[6])})
	for i: Variant in d.get("hiding", []):
		if int(i) < 0 or int(i) >= out.spots.size():
			return DotResult.fail(DotError.CODE_PARSE, "a hiding index is out of range")
		out.hiding.append(int(i))
	for row: Variant in d.get("chokepoints", []):
		if not (row is Array) or (row as Array).size() < 3:
			return DotResult.fail(DotError.CODE_PARSE, "a chokepoint row is malformed")
		out.chokepoints.append({"at": _p(row[0]), "width": float(row[1]), "traffic": float(row[2])})
	var st: Variant = d.get("stats", {})
	out.stats = st if st is Dictionary else {}
	return DotResult.success(out)


## Writes [method to_dict] as JSON to [param path] (a `user://` cache file, usually named
## after [member key]).
func save(path: String) -> DotResult:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return DotResult.fail(DotError.CODE_IO, "cannot write %s: %s" % [path, error_string(FileAccess.get_open_error())])
	f.store_string(JSON.stringify(to_dict()))
	f.close()
	# user:// in a browser is a mirror that is lost unless flushed.
	DotWeb.sync_filesystem()
	return DotResult.success(path)


## The annotations at [param path], or a failure when there is none, it does not read, or
## it was made for another key than [param expect_key] (empty to accept any).
static func load_file(path: String, expect_key: String = "") -> DotResult:
	if not FileAccess.file_exists(path):
		return DotResult.fail(DotError.CODE_IO, "no annotations at %s" % path)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return DotResult.fail(DotError.CODE_PARSE, "%s is not an annotations document" % path)
	var res := from_dict(parsed)
	if res.ok and expect_key != "" and (res.value as DotNpcAiNavAnnotations).key != expect_key:
		return DotResult.fail(DotError.CODE_INTEGRITY, "%s was made for another map or other settings" % path)
	return res


static func _v(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]


static func _p(a: Variant) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO


func describe() -> Dictionary:
	return {
		"key": key.left(12),
		"links": link_counts(),
		"spots": spots.size(),
		"hiding": hiding.size(),
		"chokepoints": chokepoints.size(),
		"stats": stats,
	}


func describe_lines() -> PackedStringArray:
	var counts := link_counts()
	var parts := PackedStringArray()
	for k: String in counts:
		parts.append("%s %d" % [k, counts[k]])
	return PackedStringArray([
		"nav annotations %s: %d links (%s), %d spots, %d hiding, %d chokepoints" % [
			key.left(12), links.size(), ", ".join(parts), spots.size(), hiding.size(), chokepoints.size()],
	])
