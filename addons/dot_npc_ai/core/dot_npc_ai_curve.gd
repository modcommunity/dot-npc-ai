class_name DotNpcAiCurve
extends RefCounted

## A response curve: maps a raw input to a 0..1 score for utility scoring. Pure and allocation-free.

enum Kind { LINEAR, QUADRATIC, LOGISTIC, INVERSE, STEP }

var kind: Kind = Kind.LINEAR
## The input range mapped to 0..1 before the curve; outside it clamps.
var lo: float = 0.0
var hi: float = 1.0
## Linear and inverse gradient; logistic steepness.
var slope: float = 1.0
## Quadratic power.
var exponent: float = 2.0
## Moves the curve along the input (fraction of the range); a logistic's midpoint is 0.5 + shift, a step's threshold too.
var shift: float = 0.0


static func make(p_kind: Kind, p_lo: float = 0.0, p_hi: float = 1.0, p_slope: float = 1.0, p_shift: float = 0.0) -> DotNpcAiCurve:
	var c := DotNpcAiCurve.new()
	c.kind = p_kind
	c.lo = p_lo
	c.hi = p_hi
	c.slope = p_slope
	c.shift = p_shift
	if p_kind == Kind.LOGISTIC and p_slope == 1.0:
		c.slope = 10.0
	return c


## The score of [param x], 0..1. [param extra_shift] is a personality's nudge of the curve's position.
func eval(x: float, extra_shift: float = 0.0) -> float:
	var span := hi - lo
	var t := 0.0 if is_zero_approx(span) else clampf((x - lo) / span, 0.0, 1.0)
	var s := shift + extra_shift
	match kind:
		Kind.LINEAR:
			return clampf(slope * (t - s), 0.0, 1.0)
		Kind.QUADRATIC:
			return pow(clampf(slope * (t - s), 0.0, 1.0), exponent)
		Kind.INVERSE:
			return 1.0 - clampf(slope * (t - s), 0.0, 1.0)
		Kind.STEP:
			return 1.0 if t >= 0.5 + s else 0.0
		Kind.LOGISTIC:
			var mid := 0.5 + s
			var f0 := 1.0 / (1.0 + exp(slope * mid))
			var f1 := 1.0 / (1.0 + exp(-slope * (1.0 - mid)))
			var f := 1.0 / (1.0 + exp(-slope * (t - mid)))
			return clampf((f - f0) / maxf(f1 - f0, 0.00001), 0.0, 1.0)
	return 0.0


func to_dictionary() -> Dictionary:
	return {"kind": String(Kind.keys()[kind]).to_lower(), "lo": lo, "hi": hi, "slope": slope, "exponent": exponent, "shift": shift}


## A curve from a dictionary (from JSON or YAML); an unknown kind is an error, never a silent linear.
static func from_dictionary(d: Dictionary) -> DotResult:
	var name := String(d.get("kind", "linear")).to_upper()
	if not Kind.has(name):
		return DotResult.fail(DotError.CODE_INVALID, "unknown curve kind '%s'" % name.to_lower())
	var c := make(Kind[name], float(d.get("lo", 0.0)), float(d.get("hi", 1.0)), float(d.get("slope", 1.0)), float(d.get("shift", 0.0)))
	c.exponent = float(d.get("exponent", 2.0))
	return DotResult.success(c)


func describe() -> String:
	return "%s[%g..%g] slope %g shift %g" % [String(Kind.keys()[kind]).to_lower(), lo, hi, slope, shift]
