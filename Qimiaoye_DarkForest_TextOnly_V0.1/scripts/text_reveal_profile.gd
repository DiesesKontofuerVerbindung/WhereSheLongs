class_name DarkForestTextRevealProfile
extends RefCounted

const SECONDS_PER_CHARACTER := 0.060
const MIN_SECONDS := 0.42
const MAX_SECONDS := 3.20
const START_ALPHA := 0.24


static func duration_for(text: String) -> float:
	return clampf(float(text.length()) * SECONDS_PER_CHARACTER, MIN_SECONDS, MAX_SECONDS)


static func is_valid() -> bool:
	return (
		SECONDS_PER_CHARACTER > 0.0
		and MAX_SECONDS > MIN_SECONDS
		and START_ALPHA > 0.0
		and START_ALPHA < 1.0
	)
