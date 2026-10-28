extends "dot_npc_ai_brain_tactics.gd"

## What [DotNpcAiBrain] notices each tick: target, damage, sounds and squad reports, into the conditions. Not a public class.


## Everything this NPC notices this tick, before anything decides.
## In this order, because each step reads the last: the target (senses have run), damage since the last think, what can be heard, what the squad said. Sets the conditions every guard and [DotNpcAiDecorator.Interrupt] reads.
func _sense() -> void:
	var c := context.conditions
	c.begin_tick()

	if npc == null or not npc.is_alive() or memory == null:
		return

	memory.forget_after = memory_time()

	var now := context.now
	var has_target := npc.has_target()

	if has_target:
		var at := target_position(Vector3.INF)

		# Perceived on this pass, as against held through dot-npc's commitment grace. The
		# senses stamp `target_seen_at` with the director's clock on every pass that sees it.
		var seen := absf(npc.target_seen_at - _world_now()) < 0.0001

		if at != Vector3.INF:
						# Tracked through the grace as well as when seen: during the grace the senses hand over the target's
						# position, and a memory that stopped at the last true sighting would send the NPC BACK to that
						# corner when the grace ran out. The search then starts where the chase ended, with the target's velocity.
			var entry := memory.sighted(npc.target_id, at, now)

			if seen:
				_report(entry, now)

		c.set_flag(DotNpcAiConditions.SEE_ENEMY if seen else DotNpcAiConditions.ENEMY_OCCLUDED)

		if npc.target_id != _last_target:
			c.set_flag(DotNpcAiConditions.NEW_ENEMY)
			# Every role on the old one is let go, or a squad's slots fill with NPCs that
			# are attacking somebody else.
			_release_roles_on(_last_target)
			# A new target is a new fight; a search half done for the old one is over.
			_end_search()
	elif _had_target:
		c.set_flag(DotNpcAiConditions.LOST_ENEMY)
		_release_roles_on(_last_target)

	_had_target = has_target
	_last_target = npc.target_id if has_target else &""

	_sense_damage(c)

	if npc.def != null and npc.health_fraction() <= low_health_fraction:
		c.set_flag(DotNpcAiConditions.LOW_HEALTH)

	_listen(c)

	if squad != null and squad.pull_reports and (squad_pull_interval <= 0.0 or context.now - _pulled_at >= squad_pull_interval):
		_pulled_at = context.now
		_report_seq = squad.pull(self, _report_seq)

	if _informed_pending:
		c.set_flag(DotNpcAiConditions.SQUAD_INFORMED)
		_informed_pending = false

	if has_target and holds_attack_slot():
		c.set_flag(DotNpcAiConditions.HAS_ATTACK_SLOT)

	if squad != null:
		if squad.tokens.enabled:
			squad.token_sight(self, c.has(DotNpcAiConditions.SEE_ENEMY), _world_now())
		squad.sweep(_world_now())


## LIGHT_DAMAGE for any hurt since the last think; HEAVY_DAMAGE when the hurt inside the window adds up to [member heavy_damage_fraction] of its health.
## A window, not one hit: heavy is how fast health is going (three quick ten-percent hits break off; one a minute does not).
func _sense_damage(c: DotNpcAiConditions) -> void:
	var now := context.now

	if _pending_damage > 0.0:
		c.set_flag(DotNpcAiConditions.LIGHT_DAMAGE)
		_damage_log.append([now, _pending_damage])
		_pending_damage = 0.0

	if _damage_log.is_empty():
		return

	var total := 0.0
	var kept: Array = []

	for hit in _damage_log:
		if now - float(hit[0]) <= heavy_damage_window:
			kept.append(hit)
			total += float(hit[1])

	_damage_log = kept

	var max_health := npc.def.max_health if npc.def != null else 0.0

	if max_health > 0.0 and total >= max_health * heavy_damage_fraction:
		c.set_flag(DotNpcAiConditions.HEAVY_DAMAGE)


## Hears what the world's [DotNpcAiSounds] has said since the last think.
func _listen(c: DotNpcAiConditions) -> void:
	if sounds == null:
		sounds = DotNpcAiSounds.of(director)

		if sounds == null:
			return

	# Nothing said since it last listened: `audible` would return nothing.
	if sounds.last_id() == _last_heard_id:
		if in_danger():
			c.set_flag(DotNpcAiConditions.HEAR_DANGER)
		return

	var world_now := _world_now()
	var hearing := character.alertness if character != null else 1.0
	var here := npc.position()
	var turn_to := Vector3.INF

	for sound in sounds.audible(here, world_now, hearing, _last_heard_id):
		match sound.kind:
			DotNpcAiSounds.Kind.DANGER:
				# The nearest danger wins. A reflex rather than a decision, so there is no
				# reaction gate: an NPC that stood still for its reaction time with a
				# grenade at its feet would read as one that had not noticed.
				if _danger_until < world_now or here.distance_to(sound.position) < here.distance_to(_danger_at):
					_danger_at = sound.position
					_danger_extent = sound.extent
					_danger_until = sound.expires_at

			DotNpcAiSounds.Kind.COMBAT:
				c.set_flag(DotNpcAiConditions.HEAR_COMBAT)
				# Attributed to its maker when the maker is somebody this NPC could fight;
				# otherwise it is a fight somewhere — an ally's, an explosion — and that is
				# still worth going to see.
				var who := sound.owner if _is_enemy(sound.owner) else NOISE
				memory.heard(who, sound.position, context.now)
				turn_to = sound.position

			DotNpcAiSounds.Kind.MOVEMENT:
				if _is_enemy(sound.owner):
					c.set_flag(DotNpcAiConditions.HEAR_ENEMY)
					memory.heard(sound.owner, sound.position, context.now)
					turn_to = sound.position

	_last_heard_id = sounds.last_id()

	if in_danger():
		c.set_flag(DotNpcAiConditions.HEAR_DANGER)

	# Turns toward what it heard when it has nothing better to look at, so its eyes — the
	# sight cone dot-npc checks — can find what its ears did.
	if turn_to != Vector3.INF and not npc.has_target():
		face(turn_to - here)


## Whether [param id] is somebody this NPC could fight: a candidate its director knows.
func _is_enemy(id: StringName) -> bool:
	if id == &"" or director == null or not director.has_method(&"candidate_position"):
		return false

	var found: Variant = director.call(&"candidate_position", id, Vector3.INF)
	return found is Vector3 and found != Vector3.INF


## Tells the squad what it sees, at most every [member report_interval].
## Only an NPC with some tactics calls out: below [constant CALLOUT_TACTICS] it fights alone, half of what makes the easy preset easy.
func _report(entry: DotNpcAiMemory.Entry, now: float) -> void:
	if squad == null or tactics() < CALLOUT_TACTICS:
		return

	if now - _last_report < report_interval:
		return

	_last_report = now
	squad.report(self, entry.id, entry.position, entry.velocity, now)


## Called by [DotNpcAiSquad.report] when a squadmate saw something. True when it was news.
func _squad_report(
	enemy: StringName, position: Vector3, velocity: Vector3, seen_at: float
) -> bool:
	if memory == null or context == null:
		return false

	var news := memory.informed(enemy, position, velocity, seen_at, context.now)

	if news:
		# A flag rather than the condition itself: this is called during ANOTHER member's
		# think, which may come after this one's, and the condition would be wiped by the
		# next `begin_tick` before anything read it.
		_informed_pending = true

	return news
