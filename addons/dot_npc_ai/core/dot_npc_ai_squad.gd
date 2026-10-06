class_name DotNpcAiSquad
extends RefCounted

## NPCs that fight together: what one sees the rest know, and only so many attack at once.
##
## [b]Slots are the idea.[/b] Twelve NPCs that each decide on their own to attack the
## nearest player arrive as a queue and stand in a line — every one of them correct, and the
## whole obviously stupid. The tactical shooters' squads solve it with a few named slots per
## squad: two may attack, one may throw a grenade, one may flank. An NPC that cannot get the
## attack slot does something else useful — surround, flank, cover, wait its turn — and the
## moment an attacker dies the slot is free and the next one steps in. That single rule is
## most of what players call "the AI is coordinated".
##
## [b]Sharing is the other half.[/b] A member that sees an enemy tells the squad, and the
## rest learn where it is — second-hand, marked as such in their [DotNpcAiMemory], with the
## sighter's velocity so they go where it is heading. A squad whose members each have to
## find you separately is a set of NPCs standing near each other.
##
## [b]Members are held weakly, by instance id.[/b] A squad pointing at its brains and every
## brain pointing at its squad is a cycle GDScript never frees; a dead NPC's brain would
## live as long as the squad. A member that has gone is dropped the next time anybody looks.
##
## dot-core only: a member is any object with the methods it is called with, which is how
## [DotNpcAiBrain] joins without this file naming it.

# No log channel: squads are made and asked every think; their decisions are the brains'.

var squad_name: StringName = &""

## instance id -> WeakRef to the member.
var _members: Dictionary = {}

## Slot name -> Array of instance ids holding it, oldest first.
var _slots: Dictionary = {}

## How many reports were passed on. For a console command and a suite.
var shared_count: int = 0


func _init(p_name: StringName = &"") -> void:
	squad_name = p_name


# --- Membership ---------------------------------------------------------------

func join(member: Object) -> void:
	if member == null:
		return

	_members[member.get_instance_id()] = weakref(member)


## Leaves, letting go of every slot held. Called on death and on unbind.
func leave(member: Object) -> void:
	if member == null:
		return

	var key := member.get_instance_id()
	_members.erase(key)
	release_all(key)


func has_member(member: Object) -> bool:
	return member != null and _members.has(member.get_instance_id())


## The members still alive, in a fixed order (by instance id) so an index is stable.
func members() -> Array[Object]:
	var out: Array[Object] = []
	var keys := _members.keys()
	keys.sort()

	for key in keys:
		var found: Object = (_members[key] as WeakRef).get_ref()

		if found == null:
			_members.erase(key)
			release_all(key)
			continue

		out.append(found)

	return out


func size() -> int:
	return members().size()


func is_empty() -> bool:
	return size() == 0


## The member with the lowest instance id. Leadership that needs no election and survives
## the leader dying: the next lowest simply is it.
func leader() -> Object:
	var all := members()
	return all[0] if not all.is_empty() else null


func is_leader(member: Object) -> bool:
	return member != null and leader() == member


## Where [param member] stands in [method members], or -1.
func index_of(member: Object) -> int:
	return members().find(member)


# --- Sharing ------------------------------------------------------------------

## [param from] saw [param enemy] at [param position] moving at [param velocity].
##
## Every other member is called with
## `_squad_report(enemy, position, velocity, seen_at)` if it has that method.
## Returns how many accepted it as news.
func report(
	from: Object, enemy: StringName, position: Vector3, velocity: Vector3, seen_at: float
) -> int:
	var told := 0

	for member in members():
		if member == from or not member.has_method(&"_squad_report"):
			continue

		if bool(member.call(&"_squad_report", enemy, position, velocity, seen_at)):
			told += 1

	shared_count += 1
	return told


# --- Slots --------------------------------------------------------------------

## Takes one of [param capacity] places in [param slot], or keeps the one already held.
##
## [b]First come, first kept.[/b] A slot holder is never displaced by a newcomer, because
## an attack that is handed to whoever asked most recently is an attack that changes hands
## every tick and is never made.
func claim(slot: StringName, member: Object, capacity: int) -> bool:
	if member == null or capacity <= 0:
		return false

	var key := member.get_instance_id()
	var holders := _live_holders(slot)

	if holders.has(key):
		return true

	if holders.size() >= capacity:
		return false

	holders.append(key)
	_slots[slot] = holders
	return true


func release(slot: StringName, member: Object) -> void:
	if member == null or not _slots.has(slot):
		return

	(_slots[slot] as Array).erase(member.get_instance_id())


## Releases every slot whose name begins with [param prefix] for [param member]. How a
## brain lets go of the attack on its old target when it changes target.
func release_prefixed(prefix: String, member: Object) -> void:
	if member == null:
		return

	var key := member.get_instance_id()

	for slot in _slots.keys():
		if String(slot).begins_with(prefix):
			(_slots[slot] as Array).erase(key)


## Releases every slot whose name ends with [param suffix] for [param member]. How a brain
## lets go of every role it held on one target — "attack:p", "flank:p" — when it changes.
func release_suffixed(suffix: String, member: Object) -> void:
	if member == null:
		return

	var key := member.get_instance_id()

	for slot in _slots.keys():
		if String(slot).ends_with(suffix):
			(_slots[slot] as Array).erase(key)


func release_all(key: int) -> void:
	for slot in _slots.keys():
		(_slots[slot] as Array).erase(key)


func holds(slot: StringName, member: Object) -> bool:
	return member != null and _live_holders(slot).has(member.get_instance_id())


## How many hold [param slot] now.
func holder_count(slot: StringName) -> int:
	return _live_holders(slot).size()


## The holders of [param slot] whose members still exist.
##
## Checked on every read rather than trusted: a member freed without leaving — a node
## freed by its world, which is how worlds end — would otherwise hold its slot for ever,
## and a squad whose two attack slots belong to the dead never attacks again.
func _live_holders(slot: StringName) -> Array:
	var holders: Array = _slots.get(slot, [])
	var live: Array = []

	for key in holders:
		var ref: WeakRef = _members.get(key)

		if ref != null and ref.get_ref() != null:
			live.append(key)

	_slots[slot] = live
	return live


func describe() -> Dictionary:
	var slots := {}

	for slot in _slots.keys():
		var count := holder_count(slot)

		if count > 0:
			slots[String(slot)] = count

	return {
		"squad": String(squad_name),
		"members": size(),
		"slots": slots,
		"shared": shared_count,
	}


func describe_lines() -> PackedStringArray:
	var d := describe()
	return PackedStringArray([
		"squad %s: %d member(s), %d report(s) shared, slots %s" % [
			d["squad"], d["members"], d["shared"], str(d["slots"])
		]
	])
