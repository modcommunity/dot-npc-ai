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

# Slots and sharing are asked every think and do not log; the token pool logs its grants and releases.

var squad_name: StringName = &""

## instance id -> WeakRef to the member.
var _members: Dictionary = {}

## The member ids sorted, rebuilt only when membership changes: members() is asked per think.
var _sorted_keys: Array = []
var _keys_dirty := false

## Slot name -> Array of instance ids holding it, oldest first.
var _slots: Dictionary = {}

## Answers worked out once a tick and shared by every member asking the same question (see
## [method memo]), and the clock reading they were worked out at.
var _memo: Dictionary = {}
var _memo_at: float = -INF

## How many reports were passed on. For a console command and a suite.
var shared_count: int = 0

## Members read the squad's reports when they think ([method pull]) instead of each report
## calling every member. Same memory at each member's think, without a call per member per report.
var pull_reports: bool = false

## The pull log: one row per report, oldest first; row i has sequence number _log_base + i.
var _log_enemy: Array = []
var _log_pos := PackedVector3Array()
var _log_vel := PackedVector3Array()
var _log_at := PackedFloat64Array()
var _log_from := PackedInt64Array()
var _log_base: int = 0

## enemy -> sequence number of its newest report; only that row is delivered.
var _latest_seq: Dictionary = {}

## Rows kept once the log is trimmed. A member that slept past them reads from the oldest kept.
const LOG_KEEP := 256

## Attack tokens: a pool with a per-target cap on top of the plain slots. Off until `tokens.enabled`.
var tokens: DotNpcAiTokenConfig = DotNpcAiTokenConfig.new()

## Counts of grants, refusals and each release reason, for describe() and suites.
var token_stats := {"granted": 0, "refused": 0, "kill": 0, "timeout": 0, "los": 0, "left": 0, "manual": 0}

const CHANNEL := "npc.ai.squad"

## The slot prefix a token release also frees, so a brain that lost its token stops holding the attack.
const ATTACK_PREFIX := "attack:"

## member id -> {"target", "taken", "until", "unseen_since"}.
var _tokens: Dictionary = {}
var _cooldown_until: Dictionary = {}
var _waiting_since: Dictionary = {}
var _last_swept: float = -INF
var _rng := RandomNumberGenerator.new()
var _rng_seed: int = -1


func _init(p_name: StringName = &"") -> void:
	squad_name = p_name


# --- Membership ---------------------------------------------------------------

func join(member: Object) -> void:
	if member == null:
		return

	var key := member.get_instance_id()

	if not _members.has(key):
		_keys_dirty = true

	_members[key] = weakref(member)


## Leaves, letting go of every slot held. Called on death and on unbind.
func leave(member: Object) -> void:
	if member == null:
		return

	var key := member.get_instance_id()

	if _members.erase(key):
		_keys_dirty = true

	_cooldown_until.erase(key)
	release_all(key)


func has_member(member: Object) -> bool:
	return member != null and _members.has(member.get_instance_id())


## The members still alive, in a fixed order (by instance id) so an index is stable.
func members() -> Array[Object]:
	var out: Array[Object] = []
	var dead: Array = []

	for key in _keys():
		var found: Object = (_members[key] as WeakRef).get_ref()

		if found == null:
			dead.append(key)
			continue

		out.append(found)

	_drop(dead)
	return out


func _keys() -> Array:
	if _keys_dirty:
		_sorted_keys = _members.keys()
		_sorted_keys.sort()
		_keys_dirty = false

	return _sorted_keys


func _drop(dead: Array) -> void:
	for key in dead:
		_members.erase(key)
		_keys_dirty = true
		release_all(key)


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
## Returns how many accepted it as news; 0 under [member pull_reports], where it is logged.
func report(
	from: Object, enemy: StringName, position: Vector3, velocity: Vector3, seen_at: float
) -> int:
	shared_count += 1

	if pull_reports:
		_log_enemy.append(enemy)
		_log_pos.append(position)
		_log_vel.append(velocity)
		_log_at.append(seen_at)
		_log_from.append(from.get_instance_id() if from != null else 0)
		_latest_seq[enemy] = _log_base + _log_enemy.size() - 1

		if _log_enemy.size() >= LOG_KEEP * 2:
			_trim_log()

		return 0

	var told := 0
	var dead: Array = []

	for key in _keys():
		var ref: WeakRef = _members.get(key)

		if ref == null:
			continue

		var member: Object = ref.get_ref()

		if member == null:
			dead.append(key)
			continue

		if member == from or not member.has_method(&"_squad_report"):
			continue

		if bool(member.call(&"_squad_report", enemy, position, velocity, seen_at)):
			told += 1

	_drop(dead)
	return told


## The sequence number the next report will get. A member starts reading here.
func report_seq() -> int:
	return _log_base + _log_enemy.size()


## Delivers to [param member] every newest-per-enemy report from [param since] on that it did
## not make, through `_squad_report`. Returns the sequence number to pass next time.
func pull(member: Object, since: int) -> int:
	var end := _log_base + _log_enemy.size()

	if member == null or since >= end:
		return end

	var own := member.get_instance_id()

	for seq in range(maxi(since, _log_base), end):
		var i := seq - _log_base
		var enemy: StringName = _log_enemy[i]

		if _log_from[i] == own or int(_latest_seq.get(enemy, -1)) != seq:
			continue

		member.call(&"_squad_report", enemy, _log_pos[i], _log_vel[i], _log_at[i])

	return end


func _trim_log() -> void:
	var cut := _log_enemy.size() - LOG_KEEP
	_log_enemy = _log_enemy.slice(cut)
	_log_pos = _log_pos.slice(cut)
	_log_vel = _log_vel.slice(cut)
	_log_at = _log_at.slice(cut)
	_log_from = _log_from.slice(cut)
	_log_base += cut

	for enemy in _latest_seq.keys():
		if int(_latest_seq[enemy]) < _log_base:
			_latest_seq.erase(enemy)


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

	if _tokens.has(key):
		_drop_token(key, &"left", _last_swept)

	_waiting_since.erase(key)


func holds(slot: StringName, member: Object) -> bool:
	return member != null and _live_holders(slot).has(member.get_instance_id())


## What was [method remember]ed under [param key] at the clock reading [param now], or null.
## Everything remembered at an earlier reading is forgotten on the first question at a new one.
##
## [b]For the questions every member of a crowd asks about the same target in one tick.[/b]
## Who else is waiting on a target, and which way the target faces, walk every member and ask
## each one's slots: eighty zombies on twelve survivors asking it each was six thousand slot
## lookups a tick, each copying a holder list. Asked once and shared it is eighty.
## [param now] must be a clock every member reads the same (the director's), not a brain's own.
func memo(key: Variant, now: float) -> Variant:
	if now != _memo_at:
		_memo.clear()
		_memo_at = now
		return null

	return _memo.get(key)


func remember(key: Variant, now: float, value: Variant) -> void:
	if now != _memo_at:
		_memo.clear()
		_memo_at = now

	_memo[key] = value


## The instance ids holding [param slot] now. One list for a caller about to ask [method holds]
## of every member, which otherwise copies the holder list once a member.
func holder_ids(slot: StringName) -> Array:
	return _live_holders(slot)


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


# --- Attack tokens ------------------------------------------------------------

## Asks for an attack token against [param target] at clock reading [param now]; true when [param member] holds one.
##
## [b]Pool, cap and queue.[/b] At most `pool_size` in all, `per_target_cap` on one target; a refused
## member waits, and when room appears the longest waiter on that target goes first so none starves.
## One that lost its token to a timeout or lost sight sits out `retake_cooldown_s`, which is what rotates attackers.
func take_token(member: Object, target: StringName, now: float) -> bool:
	if member == null:
		return false

	sweep(now)
	var key := member.get_instance_id()
	var held: Dictionary = _tokens.get(key, {})

	if not held.is_empty():
		if held["target"] == target:
			return true
		_drop_token(key, &"manual", now)

	if float(_cooldown_until.get(key, -INF)) > now:
		return false

	var on_target := 0
	for other in _tokens.values():
		if other["target"] == target:
			on_target += 1

	if _tokens.size() >= tokens.pool_size or on_target >= tokens.per_target_cap or not _is_first_waiter(key, target, now):
		var wait: Array = _waiting_since.get(key, [target, now, now])
		if wait[0] != target:
			wait = [target, now, now]
		wait[2] = now
		_waiting_since[key] = wait
		token_stats["refused"] += 1
		return false

	_waiting_since.erase(key)
	_seed_rng()
	var life := tokens.timeout_s * (1.0 - tokens.timeout_jitter * _rng.randf())
	_tokens[key] = {"target": target, "taken": now, "until": now + life, "unseen_since": INF}
	token_stats["granted"] += 1
	DotLog.debug(CHANNEL, "attack token granted", {"squad": String(squad_name), "target": String(target), "held": _tokens.size()})
	return true


## Whether [param member] holds a token now.
func has_token(member: Object) -> bool:
	return member != null and _tokens.has(member.get_instance_id())


## Tokens held now, in all or against one [param target] (empty for all).
func token_count(target: StringName = &"") -> int:
	if target == &"":
		return _tokens.size()

	var n := 0
	for held in _tokens.values():
		if held["target"] == target:
			n += 1
	return n


## Gives a token back; [param reason] is one of kill, timeout, los, left, manual, claim. Every reason but kill, left and claim starts the re-take cooldown.
func release_token(member: Object, reason: StringName, now: float) -> void:
	if member != null and _tokens.has(member.get_instance_id()):
		_drop_token(member.get_instance_id(), reason, now)


## Takes back every token held against [param target]: it died or went.
func release_target_tokens(target: StringName, now: float) -> void:
	for key in _tokens.keys():
		if _tokens[key]["target"] == target:
			_drop_token(key, &"kill", now)


## Reports whether [param member] sees its target now; a token unseen for `los_loss_s` is taken back.
func token_sight(member: Object, seen: bool, now: float) -> void:
	if member == null or not _tokens.has(member.get_instance_id()):
		return

	var held: Dictionary = _tokens[member.get_instance_id()]

	if seen:
		held["unseen_since"] = INF
	elif is_inf(float(held["unseen_since"])):
		held["unseen_since"] = now


## Takes back tokens that timed out or lost sight for too long. Cheap to call often: once per clock reading.
func sweep(now: float) -> void:
	if now == _last_swept:
		return

	_last_swept = now

	if not tokens.enabled:
		_tokens.clear()
		_cooldown_until.clear()
		_waiting_since.clear()
		return

	for key in _cooldown_until.keys():
		if float(_cooldown_until[key]) <= now or not _members.has(key):
			_cooldown_until.erase(key)

	for key in _tokens.keys():
		var held: Dictionary = _tokens[key]
		var ref: WeakRef = _members.get(key)

		if ref == null or ref.get_ref() == null:
			_drop_token(key, &"left", now)
		elif now >= float(held["until"]):
			_drop_token(key, &"timeout", now)
		elif not is_inf(float(held["unseen_since"])) and now - float(held["unseen_since"]) >= tokens.los_loss_s:
			_drop_token(key, &"los", now)

	for key in _waiting_since.keys():
		if now - float(_waiting_since[key][2]) > 60.0 or not _members.has(key):
			_waiting_since.erase(key)


func _drop_token(key: int, reason: StringName, now: float) -> void:
	var held: Dictionary = _tokens.get(key, {})

	if held.is_empty():
		return

	_tokens.erase(key)
	token_stats[String(reason)] = int(token_stats.get(String(reason), 0)) + 1

	if reason != &"kill" and reason != &"left" and reason != &"claim":
		_cooldown_until[key] = now + tokens.retake_cooldown_s

	var slot := StringName(ATTACK_PREFIX + String(held["target"]))
	if _slots.has(slot):
		(_slots[slot] as Array).erase(key)

	DotLog.debug(CHANNEL, "attack token released", {"squad": String(squad_name), "reason": String(reason), "held": _tokens.size()})


## True when no member that has waited longer on [param target] is still asking and could be served.
func _is_first_waiter(key: int, target: StringName, now: float) -> bool:
	var own: Array = _waiting_since.get(key, [])
	var mine := float(own[1]) if not own.is_empty() and own[0] == target else now

	for other in _waiting_since.keys():
		if other == key:
			continue

		var wait: Array = _waiting_since[other]
		var fresh: bool = float(wait[1]) < mine and wait[0] == target
		# A waiter that stopped asking (throttled, or gone) does not hold a free token back.
		var asking: bool = now - float(wait[2]) <= minf(tokens.wait_window_s, tokens.waiter_grace_s)

		if fresh and asking and float(_cooldown_until.get(other, -INF)) <= now and _members.has(other):
			return false

	return true


func _seed_rng() -> void:
	if _rng_seed != tokens.seed:
		_rng_seed = tokens.seed
		_rng.seed = tokens.seed


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
		"tokens": _tokens.size() if tokens.enabled else -1,
		"token_stats": token_stats.duplicate() if tokens.enabled else {},
	}


func describe_lines() -> PackedStringArray:
	var d := describe()
	var out := PackedStringArray([
		"squad %s: %d member(s), %d report(s) shared, slots %s" % [
			d["squad"], d["members"], d["shared"], str(d["slots"])
		]
	])

	if tokens.enabled:
		out.append("tokens %d/%d held (cap %d per target), %s" % [
			_tokens.size(), tokens.pool_size, tokens.per_target_cap, str(token_stats)
		])

	return out
