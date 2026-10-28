class_name DotNpcAiSquads
extends RefCounted

## Every squad in one world, by name. Put on a director so its brains can find theirs.
## A brain joins the squad its definition names (`"squad"` in its meta) or the one its game assigns. Metadata on the director, not [DotRegistry], as [DotNpcAiSkill]: two servers in one process must not share squads.

const META := &"dot_npc_ai_squads"

var _squads: Dictionary = {}

## Token settings every squad made from now on shares. Null leaves each squad its own (off) defaults.
var tokens: DotNpcAiTokenConfig = null

## [member DotNpcAiSquad.pull_reports] for every squad, made now or later.
var pull_reports: bool = false:
	set(value):
		pull_reports = value
		for found in _squads.values():
			(found as DotNpcAiSquad).pull_reports = value


## The squad called [param squad_name], made if it does not exist yet.
func squad(squad_name: StringName) -> DotNpcAiSquad:
	var found: DotNpcAiSquad = _squads.get(squad_name)

	if found == null:
		found = DotNpcAiSquad.new(squad_name)

		if tokens != null:
			found.tokens = tokens

		found.pull_reports = pull_reports

		_squads[squad_name] = found

	return found


func find(squad_name: StringName) -> DotNpcAiSquad:
	return _squads.get(squad_name)


## Drops squads nobody is in. A squad name per wave is a name per wave for ever otherwise.
func prune() -> int:
	var dropped := 0

	for key in _squads.keys():
		if (_squads[key] as DotNpcAiSquad).is_empty():
			_squads.erase(key)
			dropped += 1

	return dropped


func names() -> PackedStringArray:
	var out := PackedStringArray()

	for key in _squads.keys():
		out.append(String(key))

	return out


func attach(director: Node) -> void:
	if director != null:
		director.set_meta(META, self)


static func of(director: Object) -> DotNpcAiSquads:
	if director == null or not director.has_meta(META):
		return null

	return director.get_meta(META) as DotNpcAiSquads


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()

	for key in _squads.keys():
		out.append_array((_squads[key] as DotNpcAiSquad).describe_lines())

	return out
