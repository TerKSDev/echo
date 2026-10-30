extends Node
## Global game state (Autoload as "GameState").
## Keeps the level list, current level, and persistent audio/microphone settings
## automatically saved to `user://settings.cfg`.

const MENU_SCENE := "res://ui/screens/menu.tscn"
const MAIN_SCENE := "res://scenes/main.tscn"
const LEVEL_SELECT_SCENE := "res://ui/screens/level_select.tscn"
const SETTINGS_PATH := "user://settings.cfg"
const PROGRESS_PATH := "user://level_progress.cfg"

enum GameMode { STORY, CHALLENGE }
var current_mode: GameMode = GameMode.STORY

# Story Mode: 21 Levels (Level 0: Tutorial + Level 01 ~ Level 20)
const STORY_LEVELS: Array[String] = [
	"res://levels/level_0.tscn",
	"res://levels/level_01.tscn",
	"res://levels/level_02.tscn",
	"res://levels/level_03.tscn",
	"res://levels/level_04.tscn",
	"res://levels/level_05.tscn",
	"res://levels/level_06.tscn",
	"res://levels/level_07.tscn",
	"res://levels/level_08.tscn",
	"res://levels/level_09.tscn",
	"res://levels/level_10.tscn",
	"res://levels/level_11.tscn",
	"res://levels/level_12.tscn",
	"res://levels/level_13.tscn",
	"res://levels/level_14.tscn",
	"res://levels/level_15.tscn",
	"res://levels/level_16.tscn",
	"res://levels/level_17.tscn",
	"res://levels/level_18.tscn",
	"res://levels/level_19.tscn",
	"res://levels/level_20.tscn",
]

# Challenge Mode (Rogue-like Abyss): 21 Levels (Level 01 ~ Level 20 + Level SP as King/Boss Sector)
const CHALLENGE_LEVELS: Array[String] = [
	"res://levels/level_01.tscn",
	"res://levels/level_02.tscn",
	"res://levels/level_03.tscn",
	"res://levels/level_04.tscn",
	"res://levels/level_05.tscn",
	"res://levels/level_06.tscn",
	"res://levels/level_07.tscn",
	"res://levels/level_08.tscn",
	"res://levels/level_09.tscn",
	"res://levels/level_10.tscn",
	"res://levels/level_11.tscn",
	"res://levels/level_12.tscn",
	"res://levels/level_13.tscn",
	"res://levels/level_14.tscn",
	"res://levels/level_15.tscn",
	"res://levels/level_16.tscn",
	"res://levels/level_17.tscn",
	"res://levels/level_18.tscn",
	"res://levels/level_19.tscn",
	"res://levels/level_20.tscn",
	"res://levels/level_SP.tscn",
]

# Backwards compatibility list containing all registered game scenes
const LEVELS: Array[String] = [
	"res://levels/level_0.tscn",
	"res://levels/level_01.tscn",
	"res://levels/level_02.tscn",
	"res://levels/level_03.tscn",
	"res://levels/level_04.tscn",
	"res://levels/level_05.tscn",
	"res://levels/level_06.tscn",
	"res://levels/level_07.tscn",
	"res://levels/level_08.tscn",
	"res://levels/level_09.tscn",
	"res://levels/level_10.tscn",
	"res://levels/level_11.tscn",
	"res://levels/level_12.tscn",
	"res://levels/level_13.tscn",
	"res://levels/level_14.tscn",
	"res://levels/level_15.tscn",
	"res://levels/level_16.tscn",
	"res://levels/level_17.tscn",
	"res://levels/level_18.tscn",
	"res://levels/level_19.tscn",
	"res://levels/level_20.tscn",
	"res://levels/level_SP.tscn",
]

# Story Mode: Even, satisfying ~220m depth steps ascending from -4,200M (Abyss Origin) to -40M (Surface Breach)
const STORY_SECTORS: Array[Dictionary] = [
	{"name": "SHALLOW RING", "depth": "-4,200 M"},
	{"name": "SLEEPING GIANT", "depth": "-3,980 M"},
	{"name": "THE LIVING DOOR", "depth": "-3,760 M"},
	{"name": "DEAD QUIET", "depth": "-3,540 M"},
	{"name": "THE TOLLKEEPER", "depth": "-3,320 M"},
	{"name": "HUSH HALL", "depth": "-3,100 M"},
	{"name": "SHRIEK GALLERY", "depth": "-2,880 M"},
	{"name": "THE FLOODED STAIRS", "depth": "-2,660 M"},
	{"name": "THE WRONG ALARM", "depth": "-2,440 M"},
	{"name": "TWIN VAULTS", "depth": "-2,220 M"},
	{"name": "WHAT SLEEPS ABOVE", "depth": "-2,000 M"},
	{"name": "CATHEDRAL OF PILLARS", "depth": "-1,780 M"},
	{"name": "THE BLIND FORKS", "depth": "-1,560 M"},
	{"name": "TOMB RUN", "depth": "-1,340 M"},
	{"name": "THE DROWNED GALLERY", "depth": "-1,120 M"},
	{"name": "THREE LOCKS", "depth": "-900 M"},
	{"name": "THE LISTENING EYE", "depth": "-680 M"},
	{"name": "THE SPIRAL", "depth": "-460 M"},
	{"name": "THE BLACK LAKE", "depth": "-240 M"},
	{"name": "SURFACE BREACH", "depth": "-40 M"},
]

# Challenge Mode: Plunges from -4,500M down to -9,999M (King Sector: The Final Echo)
const CHALLENGE_SECTORS: Array[Dictionary] = [
	{"name": "ABYSS DESCENT I", "depth": "-4,500 M"},
	{"name": "HOLLOW VOID", "depth": "-4,750 M"},
	{"name": "DEEP RIFT", "depth": "-5,000 M"},
	{"name": "OBSIDIAN CHASM", "depth": "-5,250 M"},
	{"name": "SILENT LABYRINTH", "depth": "-5,500 M"},
	{"name": "ECHO SANCTUARY", "depth": "-5,750 M"},
	{"name": "SCREAMING VEIN", "depth": "-6,000 M"},
	{"name": "SUB-OCEAN TRENCH", "depth": "-6,250 M"},
	{"name": "STILLWATER ABYSS", "depth": "-6,500 M"},
	{"name": "FORBIDDEN DRIFT", "depth": "-6,750 M"},
	{"name": "ANCIENT HOLLOW", "depth": "-7,000 M"},
	{"name": "VOID NEXUS", "depth": "-7,250 M"},
	{"name": "SPECTRAL VAULT", "depth": "-7,500 M"},
	{"name": "SHADOW WELL", "depth": "-7,750 M"},
	{"name": "BLIND ABYSS", "depth": "-8,000 M"},
	{"name": "CRIMSON STRATA", "depth": "-8,250 M"},
	{"name": "FORGOTTEN CRYPT", "depth": "-8,500 M"},
	{"name": "PRIMORDIAL TRENCH", "depth": "-8,750 M"},
	{"name": "THE DARK SPINE", "depth": "-9,000 M"},
	{"name": "VOID THRESHOLD", "depth": "-9,250 M"},
	{"name": "KING SECTOR • THE FINAL ECHO", "depth": "-9,999 M"},
]

# Alias for backwards compatibility
const SECTORS: Array[Dictionary] = STORY_SECTORS

var current_level := 0
var story_highest_unlocked := 1
var challenge_highest_unlocked := 1
var story_completed := false
var challenge_unlocked := false
var has_seen_intro := false
var story_tutorial_completed := false
var force_level_0_story := false
var challenge_sp_revealed := false
var pending_challenge_unlock_modal := false
var pending_sp_king_sector_cinematic := false
var seen_act_milestones: Dictionary = {}
var seen_campaign_endings: Dictionary = {}

var highest_unlocked_level: int:
	get:
		if current_mode == GameMode.CHALLENGE:
			return challenge_highest_unlocked
		return story_highest_unlocked
	set(val):
		if current_mode == GameMode.CHALLENGE:
			challenge_highest_unlocked = val
		else:
			story_highest_unlocked = val

func is_touch_or_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios") or DisplayServer.is_touchscreen_available()


func is_story_completed() -> bool:
	return story_completed or story_highest_unlocked > STORY_LEVELS.size()


func is_challenge_completed() -> bool:
	return challenge_records.has(21) or has_seen_campaign_ending("challenge")


func get_challenge_cleared_count() -> int:
	return challenge_records.size()


func is_challenge_unlocked() -> bool:
	return challenge_unlocked or is_story_completed() or challenge_highest_unlocked > 1 or challenge_records.size() > 0

func is_story_tutorial_completed() -> bool:
	return story_tutorial_completed or story_highest_unlocked > 1 or is_level_cleared(1)

func is_level_0_story_mode() -> bool:
	if current_mode != GameMode.STORY or current_level != 0:
		return false
	if force_level_0_story:
		return true
	return not is_story_tutorial_completed()

func is_level_cleared(lvl: int) -> bool:
	return get_level_stars(lvl) > 0 or lvl < highest_unlocked_level

func mark_story_tutorial_completed() -> void:
	story_tutorial_completed = true
	force_level_0_story = false
	var cfg := ConfigFile.new()
	cfg.load(PROGRESS_PATH)
	cfg.set_value("progress", "story_tutorial_completed", true)
	cfg.save(PROGRESS_PATH)

func get_current_levels() -> Array[String]:
	if current_mode == GameMode.CHALLENGE:
		return CHALLENGE_LEVELS
	return STORY_LEVELS

func get_level_name(lvl: int) -> String:
	if current_mode == GameMode.CHALLENGE:
		var c_idx := clampi(lvl, 0, CHALLENGE_SECTORS.size() - 1)
		if c_idx >= 0 and c_idx < CHALLENGE_SECTORS.size():
			return str(CHALLENGE_SECTORS[c_idx]["name"])
		return "CHALLENGE SECTOR %02d" % (lvl + 1)

	# Story Mode
	if lvl == 0:
		return "TRAINING GROUNDS"
	var idx := lvl - 1
	if idx >= 0 and idx < STORY_SECTORS.size():
		return str(STORY_SECTORS[idx]["name"])
	return "CAVERN SECTOR %02d" % lvl

func get_level_depth_str(lvl: int) -> String:
	if current_mode == GameMode.CHALLENGE:
		var c_idx := clampi(lvl, 0, CHALLENGE_SECTORS.size() - 1)
		if c_idx >= 0 and c_idx < CHALLENGE_SECTORS.size():
			var raw: String = str(CHALLENGE_SECTORS[c_idx]["depth"])
			return "~" + raw.replace("-", "").strip_edges()
		return "~4,500 M"

	# Story Mode
	if lvl == 0:
		return "TRAINING BASE"
	var idx := lvl - 1
	if idx >= 0 and idx < STORY_SECTORS.size():
		var raw: String = str(STORY_SECTORS[idx]["depth"])
		return "~" + raw.replace("-", "").strip_edges()
	return "~0 M"


func get_level_depth(lvl: int) -> String:
	return get_level_depth_str(lvl)

# Evocative philosophical explorer recovery logs (convey positive psychological resilience & mindfulness)
const SECTOR_LOGS: Dictionary = {
	1: "In the deepest dark, silence is not emptiness—it is your canvas.",
	2: "Sound travels far down straight halls, but calmness travels further.",
	3: "Move gently. The abyss reflects only what you project.",
	4: "A quiet diversion overcomes sheer brute force.",
	5: "Patience unmasks every wall; panic only builds more.",
	6: "Listen closely: every obstacle has an echo that reveals the path forward.",
	7: "Walk with care. Subterranean pressure turns rough stone into steadfast resolve.",
	8: "Still your waters. When current drags your feet, freeze and let the terror pass.",
	9: "The loudest alarm can clear the quietest path. Wisdom turns danger into an ally.",
	10: "In the crystalline cold, clarity shines through the dark. Unlock both sides of fear.",
	11: "Step past dormant shadows. When the time comes, let courage outrun terror.",
	12: "The grandest cathedral is crossed not by haste, but by unwavering focus between pillars.",
	13: "Four paths in the gloom. Do not shout blindly; patience illuminates the true branch.",
	14: "A scattered pebble buys precious heartbeats. In ancient tombs, ingenuity outpaces the beast.",
	15: "Balance upon the dry beam above, wade through the deep below. Adaptability is survival.",
	16: "Three ancient gates fall one by one. Every seal broken brings you closer to the sky.",
	17: "The eye of the cavern listens to your every breath. Subdue your panic into absolute silence.",
	18: "Every winding ring tests your spirit. Trust the inward curve; it leads upward.",
	19: "Dark waters stretch under ancient domes. Cross the cold lake; the shore of daylight is near.",
	20: "Forty meters from the sun. The abyss awakens in fury—shatter the ceiling and step into the light.",
}

# Narrative Act Interlude beats between major subterranean strata
const ACT_MILESTONES: Dictionary = {
	6: [
		"You have climbed past the lowest stratum of silence: -3,100 Meters.",
		"The subterranean chill sharpens. Distant shrieks vibrate through the stone.",
		"The abyss is awake now. Steel your resolve as you ascend."
	],
	12: [
		"Two thousand meters beneath the surface, ancient pillars rise into the dark.",
		"These ruins were built by those who once sought to seal the shadows.",
		"Trust not what you fear. Trust only the stillness within your heart."
	],
	18: [
		"The winding spiral unravels beneath your feet: -460 Meters.",
		"The stagnant air of the deep gives way to faint underground currents.",
		"You can feel the heartbeat of the surface above. The ascent nears its end."
	]
}

# Evocative sector transition narrative beats for Story Mode ascent
const SECTOR_TRANSITIONS: Dictionary = {
	1: [
		"The resonance of the Shallow Ring fades into the deep.",
		"“In the deepest dark, silence is not emptiness—it is your canvas.”"
	],
	2: [
		"The heavy snores of the sleeping giants sink back into the silt.",
		"“Sound travels far down straight halls, but calmness travels further.”"
	],
	3: [
		"The ancient stone gates grind shut. You step into the quiet hollows above.",
		"“Move gently. The abyss reflects only what you project.”"
	],
	4: [
		"Past the crimson predators, the narrow corridor opens upward.",
		"“A quiet diversion overcomes sheer brute force.”"
	],
	5: [
		"You pay the silent toll of the deep. Ahead lies the threshold of Hush Hall.",
		"“Patience unmasks every wall; panic only builds more.”"
	],
	7: [
		"The shrill echoes of the crystal gallery fracture into silence.",
		"“Walk with care. Subterranean pressure turns rough stone into steadfast resolve.”"
	],
	8: [
		"Drenched in black water, you climb past the subterranean tide: -2,440 Meters.",
		"“Still your waters. When current drags your feet, freeze and let the terror pass.”"
	],
	9: [
		"The deceptive alarms fade into the abyss. The path upward is clear.",
		"“The loudest alarm can clear the quietest path. Wisdom turns danger into an ally.”"
	],
	10: [
		"Both ancient vaults unlocked, the cold stone stairs wind upward: -2,000 Meters.",
		"“In the crystalline cold, clarity shines through the dark. Unlock both sides of fear.”"
	],
	11: [
		"You slip past the towering dormant shadows into the grand cathedral above.",
		"“Step past dormant shadows. When the time comes, let courage outrun terror.”"
	],
	13: [
		"Through the four dark forks, patient echoes revealed the true passage.",
		"“Four paths in the gloom. Do not shout blindly; patience illuminates the true branch.”"
	],
	14: [
		"Behind you, the tomb run collapses into stillness: -1,120 Meters.",
		"“A scattered pebble buys precious heartbeats. In ancient tombs, ingenuity outpaces the beast.”"
	],
	15: [
		"Wading through the drowned gallery, you pull yourself onto the dry ledges above.",
		"“Balance upon the dry beam above, wade through the deep below. Adaptability is survival.”"
	],
	16: [
		"Three great locks dissolved into the dark. Less than a kilometer of rock remains.",
		"“Three ancient gates fall one by one. Every seal broken brings you closer to the sky.”"
	],
	17: [
		"You slip past the listening eye undetected. The winding spiral beckons: -460 Meters.",
		"“The eye of the cavern listens to your every breath. Subdue your panic into absolute silence.”"
	],
	19: [
		"Across the vast expanse of the Black Lake, cold surface air stirs the water.",
		"“Dark waters stretch under ancient domes. Cross the cold lake; the shore of daylight is near.”"
	],
}

func has_seen_act_milestone(lvl: int) -> bool:
	return seen_act_milestones.has(lvl)


func mark_act_milestone_seen(lvl: int) -> void:
	if seen_act_milestones.has(lvl):
		return
	seen_act_milestones[lvl] = true
	var cfg := ConfigFile.new()
	cfg.load(PROGRESS_PATH)
	cfg.set_value("narrative", "seen_act_milestones", seen_act_milestones.keys())
	cfg.save(PROGRESS_PATH)


func has_seen_campaign_ending(mode_key: String = "") -> bool:
	if mode_key.is_empty():
		mode_key = "challenge" if current_mode == GameMode.CHALLENGE else "story"
	return seen_campaign_endings.has(mode_key)


func mark_campaign_ending_seen(mode_key: String = "") -> void:
	if mode_key.is_empty():
		mode_key = "challenge" if current_mode == GameMode.CHALLENGE else "story"
	if seen_campaign_endings.has(mode_key):
		return
	seen_campaign_endings[mode_key] = true
	var cfg := ConfigFile.new()
	cfg.load(PROGRESS_PATH)
	cfg.set_value("narrative", "seen_campaign_endings", seen_campaign_endings.keys())
	cfg.save(PROGRESS_PATH)


func get_act_milestone_lines(lvl: int) -> Array:
	if current_mode == GameMode.STORY and ACT_MILESTONES.has(lvl):
		return ACT_MILESTONES[lvl]
	return []


func get_sector_story_lines(lvl: int) -> Array:
	if current_mode != GameMode.STORY:
		return []
	if ACT_MILESTONES.has(lvl):
		return ACT_MILESTONES[lvl]
	if SECTOR_TRANSITIONS.has(lvl):
		return SECTOR_TRANSITIONS[lvl]
	if SECTOR_LOGS.has(lvl):
		return [
			"You step onto the cold stone stairs winding upward into the dark.",
			"“%s”" % str(SECTOR_LOGS[lvl])
		]
	return []


func get_act_milestone_header(lvl: int) -> String:
	match lvl:
		6:
			return "◈   A C T   I   C L E A R E D   •   D E P T H   - 3 , 1 0 0   M   ◈"
		12:
			return "◈   A C T   I I   C L E A R E D   •   D E P T H   - 1 , 7 8 0   M   ◈"
		18:
			return "◈   A C T   I I I   C L E A R E D   •   D E P T H   - 4 6 0   M   ◈"
		_:
			var d_str: String = get_level_depth_str(lvl)
			return "◈   S E C T O R   %02d   •   D E P T H   %s   •   A S C E N T   ◈" % [lvl, d_str]


func get_campaign_ending_lines() -> Array:
	if current_mode == GameMode.CHALLENGE:
		return [
			"You stand at -9,999 Meters: the absolute core of the abyss.",
			"Here, where light has never reached, your voice was the only genesis.",
			"Every terror in the dark was an echo awaiting its answer.",
			"You did not escape the dark. You brought understanding to it.",
			"The Final Echo is complete."
		]
	return [
		"The stone crust shatters upward.",
		"A warmth you had long forgotten floods across your face.",
		"Not the cold, damp breath of the cavern, but the living wind of the sky.",
		"The pitch-black abyss dissolves into boundless daylight.",
		"You are silent no longer. The light has returned."
	]

func get_sector_log(lvl: int) -> String:
	if SECTOR_LOGS.has(lvl):
		return str(SECTOR_LOGS[lvl])
	return "Stay calm. Stay silent. Follow the light."

# Level Par Benchmarks: { level_number: { "par_time": float, "par_pings": int } }
const LEVEL_PARS: Dictionary = {
	0: { "par_time": 25.0, "par_pings": 8 },    # Tutorial
	1: { "par_time": 30.0, "par_pings": 8 },    # Shallow Ring (2.3% Water)
	2: { "par_time": 40.0, "par_pings": 10 },   # Sleeping Giant (20.4% Water)
	3: { "par_time": 40.0, "par_pings": 10 },   # The Living Door (Compact)
	4: { "par_time": 45.0, "par_pings": 10 },   # Dead Quiet (4.5% Water)
	5: { "par_time": 55.0, "par_pings": 12 },   # The Tollkeeper
	6: { "par_time": 60.0, "par_pings": 14 },   # Hush Hall
	7: { "par_time": 60.0, "par_pings": 12 },   # Shriek Gallery (Screamers)
	8: { "par_time": 80.0, "par_pings": 16 },   # The Flooded Stairs (97.8% Water)
	9: { "par_time": 65.0, "par_pings": 16 },   # The Wrong Alarm
	10: { "par_time": 80.0, "par_pings": 16 },  # Twin Vaults (Dual Keys)
	11: { "par_time": 60.0, "par_pings": 10 },  # What Sleeps Above
	12: { "par_time": 90.0, "par_pings": 20 },  # Cathedral of Pillars (1,416 Walkable Cells)
	13: { "par_time": 70.0, "par_pings": 14 },  # The Blind Forks
	14: { "par_time": 65.0, "par_pings": 12 },  # Tomb Run (10.4% Water)
	15: { "par_time": 95.0, "par_pings": 20 },  # The Drowned Gallery (72.2% Water)
	16: { "par_time": 100.0, "par_pings": 20 }, # Three Locks (Tri-Gate Run)
	17: { "par_time": 105.0, "par_pings": 22 }, # The Listening Eye
	18: { "par_time": 95.0, "par_pings": 18 },  # The Spiral
	19: { "par_time": 120.0, "par_pings": 22 }, # The Black Lake (1,724 Cells + 26.5% Water)
	20: { "par_time": 90.0, "par_pings": 18 },  # Surface Breach (Vertical Ascent)
	21: { "par_time": 140.0, "par_pings": 28 }, # King Sector: The Final Echo (1,365 Cells)
}

var level_records: Dictionary = {}
var challenge_records: Dictionary = {}
var collected_notes: Dictionary = {}

# Collectible Expedition Archives & Subterranean Lore Notes
const LORE_NOTES: Dictionary = {
	"L01_1": {
		"level": 1,
		"title": "Field Log: The Deep Plunge",
		"author": "Dr. Aris Thorne • Vanguard VII",
		"depth": "-4,200 M",
		"text": "The elevator cables snapped at 0400 hours. We plunged through four kilometers of basalt before the emergency brakes melted into the shaft. We survived, but our lanterns were smashed. Here at -4,200 meters, darkness has weight. Yet in this suffocating void, if you hold your breath, the stone hums. Sound is our only sight now."
	},
	"L02_1": {
		"level": 2,
		"title": "Biologist Note: Slumber in Silt",
		"author": "Biologist Maya Lin",
		"depth": "-3,980 M",
		"text": "We found the first specimen curled in the sediment. It has no eyes—not even vestigial sockets—only oversized tympanic membranes along its flanks. As long as we sneak, gliding our boots along the ground without lifting our heels, it remains in catatonic dormancy. Run, however, and it awakens with terrifying speed."
	},
	"L03_1": {
		"level": 3,
		"title": "Tactical Log: The Thrown Stone",
		"author": "Scout Jarek",
		"depth": "-3,760 M",
		"text": "A beast was blocking the only corridor out of the flooded chamber. Thorne took a handful of dry gravel from his pocket and threw it against the far stalactite. The clatter drew the creature away like a moth to a flame. The blind predators here don't chase you; they chase sound. Mislead their ears, and they are powerless."
	},
	"L04_1": {
		"level": 4,
		"title": "Field Log: The Crimson Hunter",
		"author": "Dr. Aris Thorne",
		"depth": "-3,540 M",
		"text": "Three apex predators block the eastern halls: Chasers. Unlike the pacing sentries, their auditory nerves are tuned exclusively to sharp acoustic spikes—they are completely deaf to creeping footsteps. Yet the moment a voice echo or normal bootstep touches them, they charge the sound origin at blinding velocity. Toss a pebble into a far alcove, then slip past in dead silence."
	},
	"L04_2": {
		"level": 4,
		"title": "Acoustic Physics: Porous Shielding",
		"author": "Engineer Kaelen",
		"depth": "-3,540 M",
		"text": "The cavern partitions here are composed of volcanic pumice. Sound waves attempting to penetrate a solid stone corner lose up to seventy percent of their kinetic amplitude. When a threat roars in the dark, do not run down an open hallway—duck behind a thick wall. Stone absorbs panic."
	},
	"L05_1": {
		"level": 5,
		"title": "Survey Note: The Pacing Sentinel",
		"author": "Dr. Aris Thorne",
		"depth": "-3,320 M",
		"text": "There are creatures that never sleep. They pace perpetual geometric loops around the megalithic pillars, tracing the same route with mechanical precision. Their gait is measured, rhythmically tapping the floor. It is almost as if they are blind sentinels stationed here eons ago to enforce an ancient quarantine."
	},
	"L06_1": {
		"level": 6,
		"title": "Monolith Log: The Hive Ear",
		"author": "Biologist Maya Lin",
		"depth": "-3,100 M",
		"text": "At the center of Hush Hall sits an emerald monolith that breathes: The Listener. It possesses no limbs, and it ignores footsteps completely, yet its tympanic core spans the entire chamber. It accumulates vocal echoes and thrown stones like sand in an hourglass. On reaching its 3rd disturbance (or 2nd under feedback curse), it broadcasts a sector-wide alarm that drives every beast toward you."
	},
	"L06_2": {
		"level": 6,
		"title": "Scout's Scrawl: The Broken Compass",
		"author": "Scout Jarek",
		"depth": "-3,100 M",
		"text": "Magnetic north is dead down here. But when you strike the stone with a boot, the echo returns faster from the near wall and slower from the distant corridor. My ears are becoming eyes. If we ever make it back to the sun, I wonder if daylight will hurt to look at."
	},
	"L07_1": {
		"level": 7,
		"title": "Autopsy Fragment: Vocal Cocoon",
		"author": "Biologist Maya Lin",
		"depth": "-2,880 M",
		"text": "In this gallery we encountered stationary organisms suspended in the dark like pulsating fuchsia cocoons: Screamers. They cannot walk, but when disturbed by two consecutive sound waves, the cocoon unleashes a deafening shriek that reverberates across the entire cavern—summoning every mobile predator in range."
	},
	"L08_1": {
		"level": 8,
		"title": "Fluid Dynamics: Viscous Drag",
		"author": "Engineer Kaelen",
		"depth": "-2,660 M",
		"text": "Subterranean aquifers have flooded these stairs. Wading through knee-deep water cuts movement speed in half, and every splash amplifies footsteps threefold. But water also reveals: when a beast wades fifty paces away, pressure ripples reach your boots long before its breathing touches your ears."
	},
	"L08_2": {
		"level": 8,
		"title": "Stillness: The Riverbed Secret",
		"author": "Maya Lin",
		"depth": "-2,660 M",
		"text": "The secret to surviving the flooded stairs is stillness. When the sentinel patrols the landing right above you, do not attempt to scramble away in the mud. Freeze. The moment your legs cease moving, the ripples dissipate into the black water, and you become just another submerged stone."
	},
	"L09_1": {
		"level": 9,
		"title": "Warning: The Resonance Chain",
		"author": "Biologist Maya Lin",
		"depth": "-2,440 M",
		"text": "Our worst fears were realized in Sector 09. When a Screamer unleashes its shriek, that shockwave pierces straight through stone walls—not only luring nearby hunters, but also feeding the Listener's resonance counter from afar. Keep the Screamers quiet, or their chain reaction will awaken the entire sector."
	},
	"L09_2": {
		"level": 9,
		"title": "Tactical Log: The Deliberate Decoy",
		"author": "Dr. Aris Thorne",
		"depth": "-2,440 M",
		"text": "We turned the Listener against its own guardians. The eastern exit was impassable, swarming with prowlers. I stood at the threshold of the north passage and deliberately shouted five times, then bolted into the upper conduit. The alarm drew every beast straight to the monolith. Chaos can be carved into an open door."
	},
	"L10_1": {
		"level": 10,
		"title": "Archaeology: The Twin Architects",
		"author": "Elena • Antiquities Scholar",
		"depth": "-2,220 M",
		"text": "These vaults were not carved by erosion. The ashlar masonry fits together without mortar, sealed by dual pressure plates. The left vault bears glyphs of slumber; the right bears glyphs of shrieking resonance. The ancient architects knew that escape requires conquering both sides of fear."
	},
	"L10_2": {
		"level": 10,
		"title": "Discarded Gear: Lightening the Load",
		"author": "Scout Jarek",
		"depth": "-2,220 M",
		"text": "Vance dropped his field kit near the right vault switch. I forbade him from retrieving it—the sentry was already turning the corner. We leave our heavy rations and metal canisters behind. Only what keeps us quiet and agile moves forward."
	},
	"L11_1": {
		"level": 11,
		"title": "Observation: Shadows on the Rafters",
		"author": "Maya Lin",
		"depth": "-2,000 M",
		"text": "Two thousand meters depth. We looked up into the darkness and saw them perched along the high vault: Crimson Chasers. They do not patrol the silt; they nest directly above the key mechanism. The instant the lock turns, their claws release. Run without hesitation when the light appears."
	},
	"L12_1": {
		"level": 12,
		"title": "Sacred Space: The Silent Nave",
		"author": "Elena • Antiquities Scholar",
		"depth": "-1,780 M",
		"text": "A subterranean cathedral spanning thousands of square meters. Twelve colossal pillars support the crushing weight of the strata above. This was once a sanctuary of an ancient acoustic civilization who worshipped silence as sacred. To them, unnecessary sound was profanity."
	},
	"L12_2": {
		"level": 12,
		"title": "Prowler Tracking: The Clockwork Loop",
		"author": "Engineer Kaelen",
		"depth": "-1,780 M",
		"text": "The three sentinels pace this cathedral like interlocking clockwork gears. One shuttles the central aisle; two orbit the pillar clusters in strict clockwise rings. When obstacles are massive and predictable, terror diminishes. Study their cadence, and the cathedral becomes an open highway."
	},
	"L13_1": {
		"level": 13,
		"title": "Warning: The Four False Mouths",
		"author": "Scout Jarek",
		"depth": "-1,560 M",
		"text": "The crossroads split into four branches, but three terminate in dead-end nest hollows choked with slumbering beasts. Only the northeast branch held the bypass switch. If you are lost, do not shout for rescue. An echo from a dead end bounces back hollow and flat. Listen for the open draft."
	},
	"L13_2": {
		"level": 13,
		"title": "Personal Diary: The Halfway Ascent",
		"author": "Maya Lin",
		"depth": "-1,560 M",
		"text": "We have climbed more than 2,600 vertical meters from the crash site. My boots are worn through, and our skin is pale as lime. But Jarek insists he smelled wet moss today—not the sulfur of the deep mantle, but surface moisture seeped through karst. We are drawing closer."
	},
	"L14_1": {
		"level": 14,
		"title": "Crypt Protocol: The Sprint Corridor",
		"author": "Dr. Aris Thorne",
		"depth": "-1,340 M",
		"text": "This was an ancient trial corridor designed for speed. The instant the key was lifted, the crypt alcoves shuddered open behind us. Three apex predators chased us down sixty meters of unbroken stone. If Vance had not hurled pebbles into the side alcoves to deflect their lunges, none of us would have cleared the trench."
	},
	"L14_2": {
		"level": 14,
		"title": "Medical Log: Adrenaline Reserve",
		"author": "Maya Lin",
		"depth": "-1,340 M",
		"text": "My fingers tremble as I write this. Sprints like that push the cardiovascular system to its absolute redline in oxygen-starved air. But the human spirit is stubborn: when silence fails, instinct takes the reins. We refuse to die down here."
	},
	"L15_1": {
		"level": 15,
		"title": "Ecology: The Drowned Gallery",
		"author": "Elena • Antiquities Scholar",
		"depth": "-1,120 M",
		"text": "A suspended stone catwalk spans across an expansive flooded gallery. The walkway is infested with dormant Screamers hanging from ceiling alcoves; the black water below is infested with Sleepers. We split our route: crawling along dry beams where voice was fatal, then dropping into the cold lake where speed was choked."
	},
	"L15_2": {
		"level": 15,
		"title": "Geothermal Survey: Crustal Thinning",
		"author": "Engineer Kaelen",
		"depth": "-1,120 M",
		"text": "The water here is glacial runoff that percolated through surface limestone millennia ago. The ambient air temperature is climbing—from four degrees at the crash site to nearly eleven degrees here. The crust above us is thinning. The surface is real."
	},
	"L16_1": {
		"level": 16,
		"title": "Fortress Protocol: The Triple Airlock",
		"author": "Dr. Aris Thorne",
		"depth": "-900 M",
		"text": "Less than a kilometer beneath the open sky. An ancient bastion seals the vertical shaft with three consecutive airlock gates. The architects knew that abyssal predators must never breach the sunlit world. Each gate requires a key from a separate wing. We had to divide our courage and move like phantoms."
	},
	"L16_2": {
		"level": 16,
		"title": "The Crossing: Invisible in Air",
		"author": "Scout Jarek",
		"depth": "-900 M",
		"text": "The Listener sits dead center at the four-way crossing. Every trip between the wings brings you within arm's reach of its acoustic core. I held my breath until my vision blurred black. To conquer the three locks, you must become invisible to the very air itself."
	},
	"L17_1": {
		"level": 17,
		"title": "The Four Ordeals: Ancient Trial",
		"author": "Elena • Antiquities Scholar",
		"depth": "-680 M",
		"text": "Four wings, four ancient trials. Northwest tests stealth against hunters; south tests timing against sentries; west tests silence against screechers; east tests endurance through water. Whoever engineered this sanctuary was testing whether an explorer had mastered every principle of subterranean survival."
	},
	"L17_2": {
		"level": 17,
		"title": "Letter to the Surface: Almost Home",
		"author": "Maya Lin",
		"depth": "-680 M",
		"text": "If anyone ever recovers this journal, know that we did not give in to despair. In the dark, you discover what you are truly made of. When you cannot rely on sight, you learn to see with your mind. We are climbing toward the morning."
	},
	"L18_1": {
		"level": 18,
		"title": "The Spiral: Geometry of Composure",
		"author": "Dr. Aris Thorne",
		"depth": "-460 M",
		"text": "A massive concentric spiral carved into the granite core. Three concentric patrol rings, each watched by a relentless sentry. The path winds inward, forcing you to pass within inches of their routes. It requires supreme composure: advance one step, wait for the patrol to pass, then slip into the inner ring."
	},
	"L18_2": {
		"level": 18,
		"title": "The Karst Draft: Wind of the Living",
		"author": "Engineer Kaelen",
		"depth": "-460 M",
		"text": "The breeze is unmistakable now. For the first time in weeks, we can feel a faint cyclical current—the planet inhaling and exhaling through karst fissures above. Four hundred and sixty meters. We can hear the distant hum of wind in the trees."
	},
	"L19_1": {
		"level": 19,
		"title": "The Black Lake: The Shrine Island",
		"author": "Elena • Antiquities Scholar",
		"depth": "-240 M",
		"text": "A vast underground lake stretches beneath a vaulted limestone cavern. In the center lies a shrine island guarded by the Listener, flanked by patrolling sentinels along both shores. Crossing this freezing expanse without disturbing the water is the final barrier. Beyond the eastern bank lies the breach."
	},
	"L19_2": {
		"level": 19,
		"title": "Final Camp: The Pearlescent Crack",
		"author": "Dr. Aris Thorne",
		"depth": "-240 M",
		"text": "We made camp on the dry limestone ledge of the Black Lake. Our rations are exhausted, our clothes are rags. But above us, through a hairline fracture in the ceiling, I saw something that brought tears to my eyes: not a flashlight, but the faint, pearlescent glimmer of dawn on wet stone. One last climb."
	},
	"L20_1": {
		"level": 20,
		"title": "The Breach: Forty Meters",
		"author": "Dr. Aris Thorne",
		"depth": "-40 M",
		"text": "Forty meters beneath the open sky. The cavern ascends in six colossal tiers toward the sanctum of the final key. The air is warm and smells of pine and ozone. But the abyss will not let go easily—the ancient guardians and apex hunters guard the breach in force. We will throw our last pebbles and run for the sun."
	},
	"L20_2": {
		"level": 20,
		"title": "Elena's Message: To the One Who Follows",
		"author": "Elena • Antiquities Scholar",
		"depth": "-40 M",
		"text": "To the wanderer who finds this note in the shadows: you have made it this far. You have learned that silence is strength, that calmness overcomes fear, and that an echo can guide the lost. Take courage. The sun is waiting just beyond the stone. Step through the gate and breathe."
	}
}

func collect_note(note_id: String) -> bool:
	if not LORE_NOTES.has(note_id):
		return false
	if collected_notes.has(note_id):
		return false
	collected_notes[note_id] = true
	var cfg := ConfigFile.new()
	cfg.load(PROGRESS_PATH)
	cfg.set_value("lore", "collected_notes", collected_notes.keys())
	cfg.save(PROGRESS_PATH)
	return true

func is_note_collected(note_id: String) -> bool:
	return collected_notes.has(note_id)

func get_collected_note_count() -> int:
	return collected_notes.size()

func get_total_note_count() -> int:
	return LORE_NOTES.size()

func get_notes_for_level(lvl: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for nid in LORE_NOTES:
		if int(LORE_NOTES[nid].get("level", 0)) == lvl:
			var item: Dictionary = LORE_NOTES[nid].duplicate()
			item["id"] = nid
			item["collected"] = is_note_collected(nid)
			result.append(item)
	return result

func get_all_notes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for nid in LORE_NOTES:
		var item: Dictionary = LORE_NOTES[nid].duplicate()
		item["id"] = nid
		item["collected"] = is_note_collected(nid)
		result.append(item)
	return result

# Audio Settings
var master_volume := 1.0
var master_muted := false
var bgm_volume := 0.8
var sfx_volume := 1.0

# Microphone Settings
const ANDROID_RECORD_AUDIO_PERMISSION := "android.permission.RECORD_AUDIO"
var mic_enabled := true
var mic_sensitivity := 0.5        # 0.0 (low/strict) .. 1.0 (high/sensitive)
var mic_noise_floor_db := -48.0   # Calibrated ambient floor in dB
var mic_calibrated := false
var mic_push_to_talk := false
var mic_permission_prompted := false

# Gameplay & Controls Settings
var sneak_hold_mode := false      # false = Toggle Sneak, true = Hold to Sneak
var fast_pulse_mode := false      # Double-tap / fast ping support
var virtual_joystick_enabled := false # false = Drag & Tap, true = Virtual Joystick
var controls_layout := "right"     # "right" = Actions Right (Left Stick), "left" = Actions Left (Right Stick)
var sound_indicator_enabled := true # Off-screen directional sound pulse visualizer
var blind_assist_mode := true     # Visually impaired acoustic navigation (exit beacon, wall echoes, obstacle cane radar)
var pebble_sensitivity := 1.0          # 0.5 .. 2.0 (50% .. 200%)
var custom_hud_layout: Dictionary = {} # {"SoundBtn": {anchor_x, offset_x, anchor_y, offset_y, scale}, ...}

# Display & Graphics Settings
var fullscreen_enabled := false
var screen_shake_intensity := 1.0  # 0.0 .. 1.0 (0%, 50%, 100%)
var sonar_glow_boost := 1.0        # 0.6 .. 1.4
var vignette_enabled := true       # Pulse vignette & chromatic threat shading
var vsync_enabled := true
var max_fps := 60                  # 60, 120, 0 (uncapped)

# Advanced Settings
var sonar_palette := "cyan"        # "cyan", "emerald", "amber", "white"

# Navigation tracking
const SETTINGS_SCENE := "res://ui/screens/settings_scene.tscn"
const ARCHIVES_SCENE := "res://ui/screens/archives_scene.tscn"
const INTEL_SCENE := ARCHIVES_SCENE
const LEADERBOARD_SCENE := "res://ui/screens/leaderboard_scene.tscn"
var previous_scene_path: String = LEVEL_SELECT_SCENE
var archives_target_section: String = "hub"
var intel_default_tab: int = 0
var leaderboard_default_sector: int = 1

# Global Procedural Subterranean Menu & UI BGM System
const BGM_SCALE: Array[float] = [0.75, 1.0, 1.125, 1.2, 1.333, 1.5, 1.6, 1.8, 2.0]
const CHALLENGE_BGM_SCALE: Array[float] = [0.667, 0.707, 0.794, 0.891, 1.0, 1.059, 1.189, 1.335, 1.414, 1.587]
var _bgm_pad_player: AudioStreamPlayer = null
var _wav_story_pad: AudioStreamWAV = null
var _wav_challenge_pad: AudioStreamWAV = null
var _wav_bgm_note: AudioStreamWAV = null
var _wav_bgm_droplet: AudioStreamWAV = null
var _bgm_note_timer := 1.2
var _bgm_drop_timer := 2.8
var _bgm_note_step := 0
var _bgm_active := false


func _ready() -> void:
	_init_audio_buses()
	load_settings()
	load_progress()
	apply_display_settings()


func _init_audio_buses() -> void:
	# 1. Master Bus Studio Limiter (prevents digital clipping/harshness during loud acoustic bursts)
	var master_idx := AudioServer.get_bus_index("Master")
	if master_idx != -1:
		var has_limiter := false
		for eff_i in AudioServer.get_bus_effect_count(master_idx):
			if AudioServer.get_bus_effect(master_idx, eff_i) is AudioEffectLimiter:
				has_limiter = true
				break
		if not has_limiter:
			var limiter := AudioEffectLimiter.new()
			limiter.ceiling_db = -0.5
			limiter.threshold_db = 0.0
			AudioServer.add_bus_effect(master_idx, limiter)

	# 2. BGM Bus
	var bgm_idx := AudioServer.get_bus_index("BGM")
	if bgm_idx == -1:
		AudioServer.add_bus()
		bgm_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bgm_idx, "BGM")
		AudioServer.set_bus_send(bgm_idx, "Master")

	# 3. SFX Bus + Environmental Subterranean Cavern Reverb
	var sfx_idx := AudioServer.get_bus_index("SFX")
	if sfx_idx == -1:
		AudioServer.add_bus()
		sfx_idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(sfx_idx, "SFX")
		AudioServer.set_bus_send(sfx_idx, "Master")

	var has_reverb := false
	for eff_i in AudioServer.get_bus_effect_count(sfx_idx):
		if AudioServer.get_bus_effect(sfx_idx, eff_i) is AudioEffectReverb:
			has_reverb = true
			break
	if not has_reverb:
		var reverb := AudioEffectReverb.new()
		reverb.room_size = 0.46       # Medium-large subterranean cavern
		reverb.damping = 0.42         # Natural limestone absorption
		reverb.spread = 0.88          # Stereo immersion
		reverb.hipass = 0.12          # Retain clean punchy sub-bass
		reverb.predelay_msec = 22.0   # 22ms early reflection gap
		reverb.dry = 0.88             # Crisp direct acoustic attack
		reverb.wet = 0.16             # Delicate, lush subterranean acoustic tail
		AudioServer.add_bus_effect(sfx_idx, reverb)

	apply_audio_settings()


func apply_audio_settings() -> void:
	var master_idx := AudioServer.get_bus_index("Master")
	if master_idx != -1:
		AudioServer.set_bus_mute(master_idx, master_muted)
		AudioServer.set_bus_volume_db(master_idx, linear_to_db(maxf(master_volume, 0.0001)))

	var bgm_idx := AudioServer.get_bus_index("BGM")
	if bgm_idx != -1:
		AudioServer.set_bus_volume_db(bgm_idx, linear_to_db(maxf(bgm_volume, 0.0001)))

	var sfx_idx := AudioServer.get_bus_index("SFX")
	if sfx_idx != -1:
		AudioServer.set_bus_volume_db(sfx_idx, linear_to_db(maxf(sfx_volume, 0.0001)))


# Effective dB threshold required to trigger a voice echo
func get_mic_trigger_db() -> float:
	var sens := clampf(mic_sensitivity, 0.0, 1.0)
	var margin: float = lerpf(46.0, 10.0, sens)
	var target_db: float = mic_noise_floor_db + margin
	var min_allowed_db: float = lerpf(-4.0, -32.0, sens)
	return clampf(maxf(target_db, min_allowed_db), -34.0, -4.0)


func is_mic_permission_granted() -> bool:
	if OS.get_name() != "Android":
		return true
	return ANDROID_RECORD_AUDIO_PERMISSION in OS.get_granted_permissions()


func request_mic_permission(on_complete: Callable = Callable()) -> void:
	if OS.get_name() != "Android":
		mic_enabled = true
		save_settings()
		if on_complete.is_valid():
			on_complete.call(true)
		return

	if is_mic_permission_granted():
		mic_enabled = true
		save_settings()
		if on_complete.is_valid():
			on_complete.call(true)
		return

	mic_permission_prompted = true
	var on_res: Callable
	on_res = func(permission: String, granted: bool) -> void:
		if permission != ANDROID_RECORD_AUDIO_PERMISSION:
			return
		if get_tree().on_request_permissions_result.is_connected(on_res):
			get_tree().on_request_permissions_result.disconnect(on_res)
		mic_enabled = granted
		save_settings()
		if on_complete.is_valid():
			on_complete.call(granted)

	if not get_tree().on_request_permissions_result.is_connected(on_res):
		get_tree().on_request_permissions_result.connect(on_res)

	OS.request_permissions()

	# Safety fallback in case OS permission dialog is dismissed without signal
	var safety_timer := get_tree().create_timer(10.0)
	safety_timer.timeout.connect(func():
		if get_tree().on_request_permissions_result.is_connected(on_res):
			get_tree().on_request_permissions_result.disconnect(on_res)
			var currently_granted: bool = is_mic_permission_granted()
			mic_enabled = currently_granted
			save_settings()
			if on_complete.is_valid():
				on_complete.call(currently_granted)
	)


func apply_display_settings() -> void:
	if fullscreen_enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = max_fps


func get_sonar_color() -> Color:
	if current_mode == GameMode.CHALLENGE and sonar_palette == "cyan":
		return Color(1.0, 0.45, 0.88, 1.0)
	match sonar_palette:
		"emerald":
			return Color(0.20, 0.95, 0.65, 1.0)
		"amber":
			return Color(1.0, 0.78, 0.28, 1.0)
		"magenta", "violet", "purple":
			return Color(1.0, 0.45, 0.88, 1.0)
		"white":
			return Color(0.95, 0.98, 1.0, 1.0)
		_:
			return Color(0.25, 0.75, 1.0, 1.0)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "master_muted", master_muted)
	cfg.set_value("audio", "bgm_volume", bgm_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)

	cfg.set_value("mic", "enabled", mic_enabled)
	cfg.set_value("mic", "sensitivity", mic_sensitivity)
	cfg.set_value("mic", "noise_floor_db", mic_noise_floor_db)
	cfg.set_value("mic", "calibrated", mic_calibrated)
	cfg.set_value("mic", "push_to_talk", mic_push_to_talk)
	cfg.set_value("mic", "permission_prompted", mic_permission_prompted)

	cfg.set_value("controls", "sneak_hold_mode", sneak_hold_mode)
	cfg.set_value("controls", "fast_pulse_mode", fast_pulse_mode)
	cfg.set_value("controls", "virtual_joystick_enabled", virtual_joystick_enabled)
	cfg.set_value("controls", "controls_layout", controls_layout)
	cfg.set_value("controls", "sound_indicator_enabled", sound_indicator_enabled)
	cfg.set_value("controls", "blind_assist_mode", blind_assist_mode)
	cfg.set_value("controls", "pebble_sensitivity", pebble_sensitivity)
	cfg.set_value("controls", "custom_hud_layout", custom_hud_layout)

	cfg.set_value("display", "fullscreen_enabled", fullscreen_enabled)
	cfg.set_value("display", "screen_shake_intensity", screen_shake_intensity)
	cfg.set_value("display", "sonar_glow_boost", sonar_glow_boost)
	cfg.set_value("display", "vignette_enabled", vignette_enabled)
	cfg.set_value("display", "vsync_enabled", vsync_enabled)
	cfg.set_value("display", "max_fps", max_fps)

	cfg.set_value("advanced", "sonar_palette", sonar_palette)
	cfg.save(SETTINGS_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		apply_audio_settings()
		apply_display_settings()
		return
	master_volume = clampf(float(cfg.get_value("audio", "master_volume", 1.0)), 0.0, 1.0)
	master_muted = (cfg.get_value("audio", "master_muted", false) == true)
	bgm_volume = clampf(float(cfg.get_value("audio", "bgm_volume", 0.8)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx_volume", 1.0)), 0.0, 1.0)

	mic_enabled = (cfg.get_value("mic", "enabled", true) == true)
	mic_sensitivity = clampf(float(cfg.get_value("mic", "sensitivity", 0.5)), 0.0, 1.0)
	mic_noise_floor_db = clampf(float(cfg.get_value("mic", "noise_floor_db", -48.0)), -54.0, -34.0)
	mic_calibrated = (cfg.get_value("mic", "calibrated", false) == true)
	mic_push_to_talk = (cfg.get_value("mic", "push_to_talk", false) == true)
	mic_permission_prompted = (cfg.get_value("mic", "permission_prompted", false) == true)

	if OS.get_name() == "Android" and not is_mic_permission_granted():
		mic_enabled = false

	sneak_hold_mode = (cfg.get_value("controls", "sneak_hold_mode", false) == true)
	fast_pulse_mode = (cfg.get_value("controls", "fast_pulse_mode", false) == true)
	virtual_joystick_enabled = (cfg.get_value("controls", "virtual_joystick_enabled", false) == true)
	controls_layout = str(cfg.get_value("controls", "controls_layout", "right"))
	sound_indicator_enabled = (cfg.get_value("controls", "sound_indicator_enabled", true) == true)
	blind_assist_mode = (cfg.get_value("controls", "blind_assist_mode", true) == true)
	pebble_sensitivity = clampf(float(cfg.get_value("controls", "pebble_sensitivity", 1.0)), 0.5, 2.5)
	custom_hud_layout = cfg.get_value("controls", "custom_hud_layout", {})

	fullscreen_enabled = (cfg.get_value("display", "fullscreen_enabled", false) == true)
	screen_shake_intensity = clampf(float(cfg.get_value("display", "screen_shake_intensity", 1.0)), 0.0, 1.0)
	sonar_glow_boost = clampf(float(cfg.get_value("display", "sonar_glow_boost", 1.0)), 0.6, 1.4)
	vignette_enabled = (cfg.get_value("display", "vignette_enabled", true) == true)
	vsync_enabled = (cfg.get_value("display", "vsync_enabled", true) == true)
	max_fps = int(cfg.get_value("display", "max_fps", 60))

	sonar_palette = str(cfg.get_value("advanced", "sonar_palette", "cyan"))

	apply_audio_settings()
	apply_display_settings()


func set_master_volume(val: float) -> void:
	master_volume = clampf(val, 0.0, 1.0)
	apply_audio_settings()
	save_settings()


func set_master_muted(muted: bool) -> void:
	master_muted = muted
	apply_audio_settings()
	save_settings()


func set_bgm_volume(val: float) -> void:
	bgm_volume = clampf(val, 0.0, 1.0)
	apply_audio_settings()
	save_settings()


func set_sfx_volume(val: float) -> void:
	sfx_volume = clampf(val, 0.0, 1.0)
	apply_audio_settings()
	save_settings()


func current_level_path() -> String:
	var lvls := get_current_levels()
	if current_level >= 0 and current_level < lvls.size():
		return lvls[current_level]
	return lvls[0]


func has_next_level() -> bool:
	return current_level + 1 < get_current_levels().size()


var _is_transitioning := false


func transition_to_scene(scene_path: String, fade_out_dur: float = 0.22, fade_in_dur: float = 0.28, on_mid_transition: Callable = Callable(), hold_black_dur: float = 0.0) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true

	var curtain_layer := CanvasLayer.new()
	curtain_layer.layer = 256
	curtain_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(curtain_layer)

	var curtain := ColorRect.new()
	curtain.set_anchors_preset(Control.PRESET_FULL_RECT)
	curtain.color = Color(0.01, 0.02, 0.04, 0.0)
	curtain.mouse_filter = Control.MOUSE_FILTER_STOP
	curtain_layer.add_child(curtain)

	var tw := curtain.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(curtain, "color:a", 1.0, fade_out_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		get_tree().paused = false
		if on_mid_transition.is_valid():
			on_mid_transition.call()
		var err := get_tree().change_scene_to_file(scene_path)
		if err != OK:
			push_error("Failed to change scene to %s: %s" % [scene_path, err])
		_sync_bgm_for_scene(scene_path)
		var fade_in := curtain.create_tween()
		fade_in.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		fade_in.tween_interval(0.04 + hold_black_dur)
		fade_in.tween_property(curtain, "color:a", 0.0, fade_in_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		fade_in.tween_callback(func():
			_is_transitioning = false
			curtain_layer.queue_free()
		)
	)


func change_level(target) -> void:
	if target is int:
		start_game(target)
	elif target is String:
		var lvls := get_current_levels()
		var actual_idx: int = lvls.find(target)
		if actual_idx != -1:
			start_game(actual_idx)
		else:
			if target == "res://levels/level_SP.tscn":
				current_mode = GameMode.CHALLENGE
				var sp_idx: int = CHALLENGE_LEVELS.find(target)
				start_game(sp_idx if sp_idx != -1 else 0)
			else:
				var glob_idx: int = LEVELS.find(target)
				if glob_idx != -1:
					start_game(glob_idx)
				else:
					transition_to_scene(target)


func start_game(level_index: int = 0) -> void:
	current_level = level_index
	transition_to_scene(MAIN_SCENE, 0.28, 0.32)


func next_level() -> void:
	if has_next_level():
		start_game(current_level + 1)
	else:
		go_to_level_select()


func restart_level(fade_out_dur: float = 0.18, fade_in_dur: float = 0.22) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true

	var curtain_layer := CanvasLayer.new()
	curtain_layer.layer = 256
	curtain_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(curtain_layer)

	var curtain := ColorRect.new()
	curtain.set_anchors_preset(Control.PRESET_FULL_RECT)
	curtain.color = Color(0.01, 0.02, 0.04, 0.0)
	curtain.mouse_filter = Control.MOUSE_FILTER_STOP
	curtain_layer.add_child(curtain)

	var tw := curtain.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(curtain, "color:a", 1.0, fade_out_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		get_tree().paused = false
		get_tree().reload_current_scene()
		var fade_in := curtain.create_tween()
		fade_in.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		fade_in.tween_interval(0.04)
		fade_in.tween_property(curtain, "color:a", 0.0, fade_in_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		fade_in.tween_callback(func():
			_is_transitioning = false
			curtain_layer.queue_free()
		)
	)


func go_to_level_select() -> void:
	transition_to_scene(LEVEL_SELECT_SCENE, 0.22, 0.28)


func go_to_menu() -> void:
	transition_to_scene(MENU_SCENE, 0.22, 0.28)


func go_to_settings(from_scene: String = "") -> void:
	if from_scene != "":
		previous_scene_path = from_scene
	else:
		var cur := get_tree().current_scene
		if cur != null and cur.scene_file_path != "":
			previous_scene_path = cur.scene_file_path
	transition_to_scene(SETTINGS_SCENE, 0.22, 0.28)


func go_to_archives(from_scene: String = "", target_section: String = "hub") -> void:
	if from_scene != "":
		previous_scene_path = from_scene
	else:
		var cur := get_tree().current_scene
		if cur != null and cur.scene_file_path != "":
			previous_scene_path = cur.scene_file_path
	archives_target_section = target_section
	transition_to_scene(ARCHIVES_SCENE, 0.22, 0.28)


func go_to_intel(from_scene: String = "", _default_tab: int = 0) -> void:
	go_to_archives(from_scene, "hub")


func go_to_leaderboard(from_scene: String = "", default_sector: int = 1) -> void:
	if from_scene != "":
		previous_scene_path = from_scene
	else:
		var cur := get_tree().current_scene
		if cur != null and cur.scene_file_path != "":
			previous_scene_path = cur.scene_file_path
	leaderboard_default_sector = default_sector
	transition_to_scene(LEADERBOARD_SCENE, 0.22, 0.28)


func return_from_settings() -> void:
	var target := previous_scene_path
	if target.is_empty():
		target = LEVEL_SELECT_SCENE
	transition_to_scene(target, 0.22, 0.28)


func go_to_previous_scene() -> void:
	return_from_settings()


func reset_to_defaults() -> void:
	master_muted = false
	master_volume = 1.0
	bgm_volume = 0.8
	sfx_volume = 1.0
	mic_enabled = is_mic_permission_granted() if OS.get_name() == "Android" else true
	mic_sensitivity = 0.5
	mic_push_to_talk = false
	sneak_hold_mode = false
	fast_pulse_mode = false
	virtual_joystick_enabled = false
	controls_layout = "right"
	sound_indicator_enabled = true
	blind_assist_mode = true
	pebble_sensitivity = 1.0
	custom_hud_layout.clear()
	fullscreen_enabled = false
	screen_shake_intensity = 1.0
	sonar_glow_boost = 1.0
	vignette_enabled = true
	vsync_enabled = true
	max_fps = 60
	sonar_palette = "cyan"
	apply_audio_settings()
	apply_display_settings()
	save_settings()


func get_default_hud_layout() -> Dictionary:
	var is_left: bool = (controls_layout == "left")
	var is_joy: bool = virtual_joystick_enabled

	var defs: Dictionary = {}

	# 1. SoundBtn (110x136)
	if is_left:
		defs["SoundBtn"] = { "anchor_x": 0.0, "offset_x": 95.0, "anchor_y": 1.0, "offset_y": -118.0, "scale": 1.0 }
	else:
		defs["SoundBtn"] = { "anchor_x": 1.0, "offset_x": -95.0, "anchor_y": 1.0, "offset_y": -118.0, "scale": 1.0 }

	# 2. SneakBtn (110x136)
	if is_joy:
		if is_left:
			defs["SneakBtn"] = { "anchor_x": 0.0, "offset_x": 213.0, "anchor_y": 1.0, "offset_y": -118.0, "scale": 1.0 }
		else:
			defs["SneakBtn"] = { "anchor_x": 1.0, "offset_x": -213.0, "anchor_y": 1.0, "offset_y": -118.0, "scale": 1.0 }
	else:
		if is_left:
			defs["SneakBtn"] = { "anchor_x": 1.0, "offset_x": -95.0, "anchor_y": 1.0, "offset_y": -118.0, "scale": 1.0 }
		else:
			defs["SneakBtn"] = { "anchor_x": 0.0, "offset_x": 95.0, "anchor_y": 1.0, "offset_y": -118.0, "scale": 1.0 }

	# 3. PebbleBtn (88x104)
	if is_left:
		defs["PebbleBtn"] = { "anchor_x": 0.0, "offset_x": 95.0, "anchor_y": 1.0, "offset_y": -258.0, "scale": 1.0 }
	else:
		defs["PebbleBtn"] = { "anchor_x": 1.0, "offset_x": -95.0, "anchor_y": 1.0, "offset_y": -258.0, "scale": 1.0 }

	# 4. PauseBtn (45x45)
	defs["PauseBtn"] = { "anchor_x": 1.0, "offset_x": -59.5, "anchor_y": 0.0, "offset_y": 59.5, "scale": 1.0 }

	# 5. MicIndicator (96x28)
	defs["MicIndicator"] = { "anchor_x": 0.5, "offset_x": 0.0, "anchor_y": 0.0, "offset_y": 52.0, "scale": 1.0 }

	# 6. LevelInfo (160x42)
	defs["LevelInfo"] = { "anchor_x": 0.0, "offset_x": 118.0, "anchor_y": 0.0, "offset_y": 63.0, "scale": 1.0 }

	return defs


func reset_progress() -> void:
	# Resets Story Mode's 20 star-bearing sectors (Levels 2 to 21) back to Sector 01.
	# Level 1 (Tutorial) does NOT need to be replayed.
	# Challenge Mode access, records, and modifiers are preserved.
	var had_challenge: bool = is_challenge_unlocked()
	story_highest_unlocked = 2
	story_completed = false
	story_tutorial_completed = true
	has_seen_intro = true
	if had_challenge:
		challenge_unlocked = true
	current_level = 1
	seen_act_milestones.clear()
	seen_campaign_endings.erase("story")
	for i in range(2, STORY_LEVELS.size() + 2):
		level_records.erase(i)
	if not level_records.has(1):
		level_records[1] = {
			"survivor": true,
			"ghost": false,
			"swift": false,
			"best_time": 999.0,
			"best_pings": 999,
			"stars": 0,
		}
	var cfg := ConfigFile.new()
	if cfg.load(PROGRESS_PATH) == OK:
		cfg.set_value("progress", "story_highest_unlocked", 2)
		cfg.set_value("progress", "highest_unlocked_level", 2)
		cfg.set_value("progress", "story_completed", false)
		cfg.set_value("progress", "story_tutorial_completed", true)
		cfg.set_value("progress", "has_seen_intro", true)
		if had_challenge:
			cfg.set_value("progress", "challenge_unlocked", true)
		cfg.set_value("narrative", "seen_act_milestones", [])
		var endings: Array = []
		if seen_campaign_endings.has("challenge"):
			endings.append("challenge")
		cfg.set_value("narrative", "seen_campaign_endings", endings)
		for i in range(2, STORY_LEVELS.size() + 2):
			var sec := "level_%02d" % i
			if cfg.has_section(sec):
				cfg.erase_section(sec)
		cfg.save(PROGRESS_PATH)


func reset_challenge_run() -> void:
	challenge_highest_unlocked = 1
	challenge_sp_revealed = false
	challenge_records.clear()
	if Engine.has_singleton("ChallengeModifiers") or get_node_or_null("/root/ChallengeModifiers") != null:
		ChallengeModifiers.reset_challenge_run()
	var cfg := ConfigFile.new()
	if cfg.load(PROGRESS_PATH) == OK:
		cfg.set_value("progress", "challenge_highest_unlocked", 1)
		cfg.set_value("progress", "challenge_sp_revealed", false)
		for i in range(1, CHALLENGE_LEVELS.size() + 2):
			var sec := "challenge_%02d" % i
			if cfg.has_section(sec):
				cfg.erase_section(sec)
		cfg.save(PROGRESS_PATH)


func mark_challenge_sp_revealed() -> void:
	challenge_sp_revealed = true
	var cfg := ConfigFile.new()
	if cfg.load(PROGRESS_PATH) == OK:
		cfg.set_value("progress", "challenge_sp_revealed", true)
		cfg.save(PROGRESS_PATH)


func set_pending_challenge_unlock_modal(val: bool) -> void:
	pending_challenge_unlock_modal = val
	var cfg := ConfigFile.new()
	if cfg.load(PROGRESS_PATH) == OK:
		cfg.set_value("progress", "pending_challenge_unlock_modal", val)
		cfg.save(PROGRESS_PATH)


func restart_challenge_from_first_sector() -> void:
	reset_challenge_run()
	start_game(0)


func mark_intro_seen() -> void:
	has_seen_intro = true
	var cfg := ConfigFile.new()
	cfg.load(PROGRESS_PATH)
	cfg.set_value("progress", "has_seen_intro", true)
	cfg.save(PROGRESS_PATH)


func load_progress() -> void:
	var cfg := ConfigFile.new()
	level_records.clear()
	collected_notes.clear()
	seen_act_milestones.clear()
	seen_campaign_endings.clear()
	if cfg.load(PROGRESS_PATH) != OK:
		story_highest_unlocked = 1
		challenge_highest_unlocked = 1
		story_completed = false
		challenge_unlocked = false
		has_seen_intro = false
		story_tutorial_completed = false
		force_level_0_story = false
		return

	var raw_notes: Array = cfg.get_value("lore", "collected_notes", [])
	for nid in raw_notes:
		collected_notes[str(nid)] = true

	var raw_act_milestones: Array = cfg.get_value("narrative", "seen_act_milestones", [])
	for lvl in raw_act_milestones:
		seen_act_milestones[int(lvl)] = true

	var raw_endings: Array = cfg.get_value("narrative", "seen_campaign_endings", [])
	for end_key in raw_endings:
		seen_campaign_endings[str(end_key)] = true

	if not cfg.has_section("narrative"):
		for m_lvl in ACT_MILESTONES.keys():
			if story_highest_unlocked > int(m_lvl):
				seen_act_milestones[int(m_lvl)] = true
		if story_completed or story_highest_unlocked > STORY_LEVELS.size():
			seen_campaign_endings["story"] = true
		if challenge_highest_unlocked > CHALLENGE_LEVELS.size():
			seen_campaign_endings["challenge"] = true

	var legacy_highest: int = int(cfg.get_value("progress", "highest_unlocked_level", 1))
	story_highest_unlocked = clampi(
		int(cfg.get_value("progress", "story_highest_unlocked", legacy_highest)),
		1,
		STORY_LEVELS.size() + 1
	)
	challenge_highest_unlocked = clampi(
		int(cfg.get_value("progress", "challenge_highest_unlocked", 1)),
		1,
		CHALLENGE_LEVELS.size() + 1
	)
	story_completed = (cfg.get_value("progress", "story_completed", story_highest_unlocked > STORY_LEVELS.size()) == true)
	challenge_unlocked = (cfg.get_value("progress", "challenge_unlocked", false) == true) \
		or (challenge_highest_unlocked > 1) \
		or story_completed \
		or (story_highest_unlocked > STORY_LEVELS.size())
	has_seen_intro = (cfg.get_value("progress", "has_seen_intro", false) == true)
	story_tutorial_completed = (cfg.get_value("progress", "story_tutorial_completed", story_highest_unlocked > 1) == true)
	challenge_sp_revealed = (cfg.get_value("progress", "challenge_sp_revealed", false) == true)
	pending_challenge_unlock_modal = (cfg.get_value("progress", "pending_challenge_unlock_modal", false) == true)

	var max_entries := maxi(STORY_LEVELS.size(), CHALLENGE_LEVELS.size()) + 2
	for i in range(1, max_entries + 1):
		var sec := "level_%02d" % i
		if cfg.has_section(sec):
			level_records[i] = {
				"survivor": (cfg.get_value(sec, "survivor", true) == true),
				"ghost": (cfg.get_value(sec, "ghost", false) == true),
				"swift": (cfg.get_value(sec, "swift", false) == true),
				"best_time": float(cfg.get_value(sec, "best_time", 999.0)),
				"best_pings": int(cfg.get_value(sec, "best_pings", 999)),
				"stars": int(cfg.get_value(sec, "stars", 1)),
			}

	challenge_records.clear()
	for i in range(1, CHALLENGE_LEVELS.size() + 2):
		var sec := "challenge_%02d" % i
		if cfg.has_section(sec):
			challenge_records[i] = {
				"best_time": float(cfg.get_value(sec, "best_time", 999.0)),
				"best_pings": int(cfg.get_value(sec, "best_pings", 999))
			}
	if challenge_records.size() > 0:
		challenge_unlocked = true


func get_level_par(lvl: int) -> Dictionary:
	var par_key: int = lvl - 1 if (current_mode == GameMode.STORY and lvl > 0) else lvl
	if LEVEL_PARS.has(par_key):
		return LEVEL_PARS[par_key]
	if LEVEL_PARS.has(lvl):
		return LEVEL_PARS[lvl]
	return { "par_time": 45.0, "par_pings": 12 }


func get_level_stars(lvl: int) -> int:
	if current_mode == GameMode.CHALLENGE:
		return 0 # Challenge mode does not use stars
	if level_records.has(lvl):
		return int(level_records[lvl].get("stars", 0))
	return 0


func get_level_best_time(lvl: int) -> float:
	if current_mode == GameMode.CHALLENGE:
		if challenge_records.has(lvl):
			return float(challenge_records[lvl].get("best_time", 0.0))
		return 0.0
	if level_records.has(lvl):
		return float(level_records[lvl].get("best_time", 0.0))
	return 0.0


func is_level_ghost_cleared(lvl: int) -> bool:
	if current_mode == GameMode.CHALLENGE:
		return false
	if level_records.has(lvl):
		return (level_records[lvl].get("ghost", false) == true)
	return false


func get_total_challenge_time() -> float:
	var total := 0.0
	for lvl in challenge_records:
		total += float(challenge_records[lvl].get("best_time", 0.0))
	return total


func record_level_clear(level_number: int, clear_time: float, pings: int, alerts: int) -> Dictionary:
	# Unlock next level in campaign
	complete_level(level_number)

	var par: Dictionary = get_level_par(level_number)
	var par_time: float = float(par.get("par_time", 45.0))
	var par_pings: int = int(par.get("par_pings", 12))

	var is_survivor := true
	var is_ghost := (alerts == 0)
	var is_swift := (clear_time <= par_time)

	if current_mode == GameMode.CHALLENGE:
		var prior_rec: Dictionary = challenge_records.get(level_number, {
			"best_time": 999.0,
			"best_pings": 999
		})
		var chal_prior_best_time: float = float(prior_rec.get("best_time", 999.0))
		var chal_new_best_time: float = minf(chal_prior_best_time, clear_time)
		var chal_new_best_pings: int = mini(int(prior_rec.get("best_pings", 999)), pings)
		challenge_records[level_number] = {
			"best_time": chal_new_best_time,
			"best_pings": chal_new_best_pings
		}

		var chal_cfg := ConfigFile.new()
		chal_cfg.load(PROGRESS_PATH)
		chal_cfg.set_value("progress", "challenge_highest_unlocked", challenge_highest_unlocked)
		var chal_sec := "challenge_%02d" % level_number
		chal_cfg.set_value(chal_sec, "best_time", chal_new_best_time)
		chal_cfg.set_value(chal_sec, "best_pings", chal_new_best_pings)
		chal_cfg.save(PROGRESS_PATH)

		return {
			"level_number": level_number,
			"clear_time": clear_time,
			"pings": pings,
			"alerts": alerts,
			"par_time": par_time,
			"par_pings": par_pings,
			"is_survivor": is_survivor,
			"is_ghost": is_ghost,
			"is_swift": is_swift,
			"run_stars": 0,
			"total_stars": 0,
			"is_new_best_time": (clear_time < chal_prior_best_time),
			"is_challenge": true
		}

	var rec: Dictionary = level_records.get(level_number, {
		"survivor": false,
		"ghost": false,
		"swift": false,
		"best_time": 999.0,
		"best_pings": 999,
		"stars": 0
	})

	var prior_ghost: bool = (rec.get("ghost", false) == true)
	var prior_swift: bool = (rec.get("swift", false) == true)
	var prior_best_time: float = float(rec.get("best_time", 999.0))
	var prior_best_pings: int = int(rec.get("best_pings", 999))

	var new_ghost: bool = prior_ghost or is_ghost
	var new_swift: bool = prior_swift or is_swift
	var new_best_time: float = minf(prior_best_time, clear_time)
	var new_best_pings: int = mini(prior_best_pings, pings)

	var total_stars := 1 + (1 if new_ghost else 0) + (1 if new_swift else 0)
	var run_stars := 1 + (1 if is_ghost else 0) + (1 if is_swift else 0)

	rec["survivor"] = true
	rec["ghost"] = new_ghost
	rec["swift"] = new_swift
	rec["best_time"] = new_best_time
	rec["best_pings"] = new_best_pings
	rec["stars"] = total_stars
	level_records[level_number] = rec

	# Save records to progress config
	var cfg := ConfigFile.new()
	cfg.load(PROGRESS_PATH)
	cfg.set_value("progress", "highest_unlocked_level", highest_unlocked_level)
	var sec := "level_%02d" % level_number
	cfg.set_value(sec, "survivor", true)
	cfg.set_value(sec, "ghost", new_ghost)
	cfg.set_value(sec, "swift", new_swift)
	cfg.set_value(sec, "best_time", new_best_time)
	cfg.set_value(sec, "best_pings", new_best_pings)
	cfg.set_value(sec, "stars", total_stars)
	cfg.save(PROGRESS_PATH)

	return {
		"level_number": level_number,
		"clear_time": clear_time,
		"pings": pings,
		"alerts": alerts,
		"par_time": par_time,
		"par_pings": par_pings,
		"is_survivor": is_survivor,
		"is_ghost": is_ghost,
		"is_swift": is_swift,
		"run_stars": run_stars,
		"total_stars": total_stars,
		"is_new_best_time": (clear_time < prior_best_time),
		"is_challenge": false
	}


func complete_level(level_number: int) -> void:
	var active_levels := get_current_levels()
	if level_number < 1 or level_number > active_levels.size():
		return

	# Complete current level and unlock next level
	var next_unlocked := mini(level_number + 1, active_levels.size() + 1)

	if current_mode == GameMode.STORY:
		if next_unlocked > story_highest_unlocked:
			story_highest_unlocked = next_unlocked
		if level_number >= active_levels.size() or story_highest_unlocked > active_levels.size():
			story_completed = true
			challenge_unlocked = true
	else:
		if next_unlocked > challenge_highest_unlocked:
			challenge_highest_unlocked = next_unlocked

	var cfg := ConfigFile.new()
	cfg.load(PROGRESS_PATH)
	cfg.set_value("progress", "highest_unlocked_level", story_highest_unlocked)
	cfg.set_value("progress", "story_highest_unlocked", story_highest_unlocked)
	cfg.set_value("progress", "challenge_highest_unlocked", challenge_highest_unlocked)
	cfg.set_value("progress", "story_completed", story_completed)
	cfg.set_value("progress", "challenge_unlocked", is_challenge_unlocked())
	var error := cfg.save(PROGRESS_PATH)

	if error != OK:
		push_error("Failed to save level progress: %s" % error)


func start_menu_bgm() -> void:
	if _bgm_pad_player == null:
		_setup_menu_bgm()
	_bgm_active = true
	if _bgm_pad_player != null and not _bgm_pad_player.playing:
		_bgm_pad_player.volume_db = -26.0
		_bgm_pad_player.play()
		var tw := create_tween()
		tw.tween_property(_bgm_pad_player, "volume_db", -7.5, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func stop_menu_bgm(fade_dur: float = 0.4) -> void:
	_bgm_active = false
	if _bgm_pad_player != null and _bgm_pad_player.playing:
		var tw := create_tween()
		tw.tween_property(_bgm_pad_player, "volume_db", -40.0, fade_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func():
			if not _bgm_active and _bgm_pad_player != null:
				_bgm_pad_player.stop()
		)


func _setup_menu_bgm() -> void:
	_wav_story_pad = SfxManager.get_menu_bgm_pad()
	_wav_challenge_pad = SfxManager.get_challenge_bgm_pad()
	_wav_bgm_note = SfxManager.get_menu_bgm_note()
	_wav_bgm_droplet = SfxManager.get_menu_bgm_droplet()

	_bgm_pad_player = AudioStreamPlayer.new()
	_bgm_pad_player.name = "GlobalMenuBGM"
	_bgm_pad_player.stream = _wav_challenge_pad if current_mode == GameMode.CHALLENGE else _wav_story_pad
	_bgm_pad_player.bus = &"BGM"
	_bgm_pad_player.volume_db = -26.0
	add_child(_bgm_pad_player)


func update_bgm_for_mode() -> void:
	if _bgm_pad_player == null:
		_setup_menu_bgm()
	var is_chal: bool = (current_mode == GameMode.CHALLENGE)
	var target_stream: AudioStreamWAV = _wav_challenge_pad if is_chal else _wav_story_pad
	if _bgm_pad_player.stream != target_stream:
		var tw := create_tween()
		tw.tween_property(_bgm_pad_player, "volume_db", -36.0, 0.30).set_trans(Tween.TRANS_SINE)
		tw.tween_callback(func():
			if _bgm_pad_player != null:
				_bgm_pad_player.stream = target_stream
				_bgm_pad_player.play()
		)
		tw.tween_property(_bgm_pad_player, "volume_db", -6.5 if is_chal else -7.5, 0.45).set_trans(Tween.TRANS_SINE)


func _process(delta: float) -> void:
	if not _bgm_active or _bgm_pad_player == null or not _bgm_pad_player.playing:
		return

	var is_chal: bool = (current_mode == GameMode.CHALLENGE)
	var active_scale: Array[float] = CHALLENGE_BGM_SCALE if is_chal else BGM_SCALE
	var target_vol: float = -6.5 if is_chal else -7.5
	_bgm_pad_player.volume_db = lerpf(_bgm_pad_player.volume_db, target_vol, clampf(delta * 4.0, 0.0, 1.0))

	# Generative crystalline / abyssal echo notes
	_bgm_note_timer -= delta
	if _bgm_note_timer <= 0.0:
		_bgm_note_timer = randf_range(2.4, 4.2) if is_chal else randf_range(2.8, 4.8)
		var motif_indices: Array[int]
		if is_chal:
			# Ominous, brooding descent motif with tension and release
			motif_indices = [0, 4, 1, 5, 2, 8, 4, 0, 5, 1, 6, 2]
		else:
			motif_indices = [1, 4, 3, 1, 5, 3, 2, 0, 1, 6, 4, 3]

		var idx: int = motif_indices[_bgm_note_step % motif_indices.size()]
		_bgm_note_step += 1
		var pitch: float = active_scale[idx % active_scale.size()]
		var note_pitch: float = pitch * (0.84 if is_chal else 1.0)
		_play_bgm_sfx(_wav_bgm_note, randf_range(-11.5, -8.0), note_pitch)

		if randf() < (0.55 if is_chal else 0.45):
			var ans_step: int = (idx + (1 if is_chal else 2)) % active_scale.size()
			var ans_pitch: float = active_scale[ans_step] * (0.84 if is_chal else 1.0)
			get_tree().create_timer(0.40 if is_chal else 0.44).timeout.connect(func():
				if _bgm_active:
					_play_bgm_sfx(_wav_bgm_note, -13.0 if is_chal else -13.5, ans_pitch)
			)

	# Subterranean cavern water droplets (deeper, heavier drops in the abyss)
	_bgm_drop_timer -= delta
	if _bgm_drop_timer <= 0.0:
		_bgm_drop_timer = randf_range(3.8, 6.8) if is_chal else randf_range(4.2, 7.8)
		var drop_pitch: float = randf_range(0.68, 0.98) if is_chal else randf_range(0.84, 1.26)
		_play_bgm_sfx(_wav_bgm_droplet, randf_range(-12.5, -9.0), drop_pitch)


func _play_bgm_sfx(stream: AudioStreamWAV, vol_db: float, pitch: float) -> void:
	if stream == null or not _bgm_active:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = vol_db
	player.pitch_scale = pitch
	player.bus = &"BGM"
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _sync_bgm_for_scene(target_path: String) -> void:
	if "headphone_warning" in target_path or "intro_cutscene" in target_path:
		stop_menu_bgm(0.1)
	elif target_path == MAIN_SCENE or target_path.begins_with("res://levels/"):
		stop_menu_bgm(0.35)
	else:
		start_menu_bgm()
