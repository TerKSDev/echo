class_name EnemyPresets
## Stats for the 5 enemy types. Tuned against the player: walk 185, sneak 100.
## Index order matches Enemy.EnemyType (SLEEPER, PATROLLER, CHASER, SCREAMER, LISTENER).
## init_state: 0 = SLEEP, 1 = PATROL (see Enemy.State).
##
## How far a sound is heard: distance <= radius * (1 - hearing_threshold / loudness)
##   player walk step  0.22 -> radius 185    sneak step 0.03 -> radius 60
##   player voice 0.3~0.6 -> radius 238~436  (capped by hearing_range)
## Everything awake also notices the player within 90px (60px while sneaking).

const PRESETS: Array[Dictionary] = [
	{ # SLEEPER - hard to wake (walk ~67px), slow chase, deaf to sneaking
		"hearing_range": 350.0, "hearing_threshold": 0.14,
		"can_hear_sneak": false, "can_hear_walk": true, "can_hear_voice": true,
		"patrol_speed": 60.0, "chase_speed": 135.0,
		"alert_time": 0.85, "investigate_timeout": 3.0,
		"init_state": 0, "sleep_wake_radius": 65.0, "sneak_wake_radius": 28.0, "sneak_sense_radius": 24.0,
		"color": Color(0.68, 0.42, 0.98), # Amethyst purple
	},
	{ # PATROLLER - walks a route, hears walking (~152px) but not distant sneaking
		"hearing_range": 400.0, "hearing_threshold": 0.04,
		"can_hear_sneak": true, "can_hear_walk": true, "can_hear_voice": true,
		"patrol_speed": 75.0, "chase_speed": 150.0,
		"alert_time": 0.7, "investigate_timeout": 3.5,
		"init_state": 1, "sleep_wake_radius": 75.0, "sneak_wake_radius": 36.0, "sneak_sense_radius": 32.0,
		"color": Color(1.0, 0.82, 0.25), # Amber gold
	},
	{ # CHASER - most sensitive (walk ~160px), very fast, longer chase, deaf to sneaking
		"hearing_range": 300.0, "hearing_threshold": 0.03,
		"can_hear_sneak": false, "can_hear_walk": true, "can_hear_voice": true,
		"patrol_speed": 90.0, "chase_speed": 202.0,
		"alert_time": 0.65, "investigate_timeout": 5.0,
		"init_state": 1, "sleep_wake_radius": 75.0, "sneak_wake_radius": 30.0, "sneak_sense_radius": 24.0,
		"color": Color(1.0, 0.18, 0.18), # Crimson
	},
	{ # SCREAMER - stationary, shrieks on the 2nd voice (>= 1s apart), ignores footsteps
		"hearing_range": 450.0, "hearing_threshold": 0.08,
		"can_hear_sneak": false, "can_hear_walk": false, "can_hear_voice": true,
		"patrol_speed": 0.0, "chase_speed": 0.0,
		"alert_time": 0.8, "investigate_timeout": 3.5,
		"init_state": 0, "sleep_wake_radius": 50.0, "sneak_wake_radius": 25.0, "sneak_sense_radius": 24.0,
		"color": Color(0.95, 0.28, 0.72), # Fuchsia
	},
	{ # LISTENER - stationary, deaf to ALL footsteps, counts voices (>= 0.8s apart) up to 5
		"hearing_range": 500.0, "hearing_threshold": 0.02,
		"can_hear_sneak": false, "can_hear_walk": false, "can_hear_voice": true,
		"patrol_speed": 0.0, "chase_speed": 0.0,
		"alert_time": 0.8, "investigate_timeout": 3.5,
		"init_state": 0, "sleep_wake_radius": 60.0, "sneak_wake_radius": 25.0, "sneak_sense_radius": 24.0,
		"color": Color(0.2, 0.94, 0.68), # Emerald
	},
]


static func apply(enemy: Node, type_index: int) -> void:
	var preset: Dictionary = PRESETS[clampi(type_index, 0, PRESETS.size() - 1)]
	for key in preset:
		if key != "color":
			enemy.set(key, preset[key])


static func color_of(type_index: int) -> Color:
	return PRESETS[clampi(type_index, 0, PRESETS.size() - 1)]["color"]
