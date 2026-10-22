class_name DotNpcAiAvoidanceConfig
extends DotConfig

## Every number of [DotNpcAiAvoidance]. Layered like any DotConfig: defaults, JSON, environment, command line.

## Off by default: with it off, or no avoidance node registered, an NPC steers exactly as before.
@export var enabled: bool = false

## "auto" uses the navigation server's RVO where it is available and the own pass where not; "rvo" and "separation" force one (rvo still falls back when unavailable).
@export var backend: String = "auto"

@export_group("Agents")
## Body radius in metres when an agent does not give its own.
@export_range(0.05, 10.0, 0.05) var radius: float = 0.45
## Seconds ahead a collision with another agent is looked for.
@export_range(0.1, 10.0, 0.1) var horizon: float = 1.5
## Most neighbours one agent reacts to; the nearest are kept.
@export_range(1, 32, 1) var max_neighbours: int = 6
## Metres within which another agent counts as a neighbour.
@export_range(0.5, 50.0, 0.5) var neighbour_range: float = 4.0
## Most candidates looked at in the grid for one agent, so a pile of two hundred costs what ten do.
@export_range(4, 256, 1) var max_scan: int = 16
## Share of its speed an agent keeps going forward while stepping aside, so a pair never both stop.
@export_range(0.0, 1.0, 0.05) var min_forward: float = 0.35

@export_group("Cost")
## Calmest scheduler tier that is still avoided; above it an NPC keeps its wanted velocity.
@export_range(0, 3, 1) var max_tier: int = 1
## Ticks between recomputations for an agent in tier 1 or above (tier 0 every tick).
@export_range(1, 60, 1) var calm_interval: int = 2
## Ticks an agent may go without a steer call before it is forgotten.
@export_range(1, 6000, 1) var forget_ticks: int = 120
## Grid cell size in metres; about the neighbour range.
@export_range(0.5, 50.0, 0.5) var cell_size: float = 4.0
