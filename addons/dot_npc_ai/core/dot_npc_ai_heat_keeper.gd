class_name DotNpcAiHeatKeeper
extends RefCounted

## Keeps a [DotNpcAiHeatmap] per map: samples players, swaps it on a map change (saving the old one first, or map B trains on map A's corridors) and saves it so a server keeps learning.
## [codeblock]var heat := DotNpcAiHeatKeeper.new("user://npc_heat", "arena")
## heat.tick(delta, map_id, player_positions, spawner.now(), spawner)  # every tick; heat.save(spawner.now()) on the way out[/codeblock]

const CHANNEL := "npc.ai.heat"

## Where the files go, and the game's name in front of each map's, so two games sharing a
## user directory do not learn each other's maps.
var directory: String = "user://npc_heat"
var game_id: String = "game"

## Seconds between two samples of where the players are.
var sample_every: float = 0.5

## Seconds between saves, so a crash loses minutes of learning and not a day.
var save_every: float = 120.0

## The heat map for [member map_id]. Never null.
var heatmap: DotNpcAiHeatmap = DotNpcAiHeatmap.new()

var map_id: StringName = &""

## Whether files are read and written. Off for a suite or a client that only plays.
var persist: bool = true

var _since_sample: float = 0.0
var _since_save: float = 0.0


func _init(p_directory: String = "user://npc_heat", p_game_id: String = "game") -> void:
	directory = p_directory
	game_id = p_game_id


## One tick: swap maps if [param p_map_id] changed, sample [param positions] on the
## interval, save on the interval. Attaches the heat map to [param director] whenever it
## changes, so the brains it spawns find the right one.
func tick(
	delta: float, p_map_id: StringName, positions: Array, now: float, director: Node = null
) -> void:
	if p_map_id != map_id:
		adopt(p_map_id, now, director)

	_since_sample += delta
	_since_save += delta

	if _since_sample >= sample_every:
		_since_sample = 0.0

		for at in positions:
			heatmap.record(DotNpcAiHeatmap.TRAFFIC, at, now)

	if persist and _since_save >= save_every:
		_since_save = 0.0
		save(now)


## Saves the current map's heat and loads [param p_map_id]'s.
## Adopting the map already held reloads it WITHOUT saving first: saving would overwrite the file with the few seconds learned since [member persist] was switched on.
func adopt(p_map_id: StringName, now: float, director: Node = null) -> void:
	if p_map_id != map_id:
		save(now)

	map_id = p_map_id
	heatmap = DotNpcAiHeatmap.new()

	if persist and map_id != &"":
		var loaded := DotNpcAiHeatmap.load_from(path_for(map_id), now)

		if loaded.ok:
			heatmap = loaded.value
		else:
			DotLog.warn(CHANNEL, "a map's learned traffic could not be read; starting it again", {
				"map": String(map_id), "why": loaded.error.message,
			})

	if director != null:
		heatmap.attach(director)


## Records a player's death at [param at] into [constant DotNpcAiHeatmap.DEATHS].
func record_death(at: Vector3, now: float) -> void:
	heatmap.record(DotNpcAiHeatmap.DEATHS, at, now)


func save(now: float) -> void:
	if not persist or map_id == &"":
		return

	DirAccess.make_dir_recursive_absolute(directory)
	var saved := heatmap.save(path_for(map_id), now)

	if not saved.ok:
		DotLog.warn(CHANNEL, "a map's learned traffic could not be saved", {
			"map": String(map_id), "why": saved.error.message,
		})


func path_for(p_map_id: StringName) -> String:
	return "%s/%s_%s.json" % [directory, game_id, String(p_map_id).validate_filename()]


func describe() -> Dictionary:
	var out := heatmap.describe()
	out["map"] = String(map_id)
	out["persist"] = persist
	return out
