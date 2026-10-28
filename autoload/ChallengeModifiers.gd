extends Node

## Centralized Roguelite Challenge Mode Modifiers Manager for ECHO.
## Tracks up to 5 paired Curses (Debuffs) and Boons (Buffs) selected at milestone sectors (1, 5, 10, 15, 20).

signal pact_claimed(milestone_lvl: int, curse_id: String, boon_id: String)
signal modifiers_updated

const MILESTONES: Array[int] = [1, 5, 10, 15, 20]

# --- 10 DEBUFF REGISTRY (深渊诅咒) ---
const CURSES: Dictionary = {
	"curse_swift_predators": {
		"id": "curse_swift_predators",
		"name": "疾影狂暴",
		"title_en": "SWIFT PREDATORS",
		"flavor": "深渊中的怪物感应更加嗜血，动作异常迅捷。",
		"flavor_en": "The creatures of the deep grow frantic and predatory.",
		"description": "所有敌人的巡逻与追击移动速度提升 15%",
		"desc_en": "Enemy patrol and pursuit speeds increased by 15%",
		"icon": "skull",
		"color": Color(1.0, 0.28, 0.42)
	},
	"curse_extended_hunt": {
		"id": "curse_extended_hunt",
		"name": "绝命搜捕",
		"title_en": "RELENTLESS HUNT",
		"flavor": "残余声波挥之不去，掠食者绝不轻易放弃目标。",
		"flavor_en": "Echoes linger on the walls; predators refuse to abandon the chase.",
		"description": "敌人丢失声源后的警惕搜寻时间延长 75%",
		"desc_en": "Enemy alert search duration extended by 75% after losing contact",
		"icon": "radar",
		"color": Color(0.95, 0.35, 0.20)
	},
	"curse_acute_hearing": {
		"id": "curse_acute_hearing",
		"name": "敏锐听觉",
		"title_en": "ACUTE HEARING",
		"flavor": "岩壁传导细微震颤，任何声响都将被放大捕获。",
		"flavor_en": "Vibrations conduct through rock, amplifying the softest sounds.",
		"description": "所有敌人的声音感知与警戒距离扩大 30%",
		"desc_en": "Enemy acoustic perception and hearing range expanded by 30%",
		"icon": "ear",
		"color": Color(1.0, 0.45, 0.25)
	},
	"curse_treacherous_waters": {
		"id": "curse_treacherous_waters",
		"name": "深渊浊水",
		"title_en": "TREACHEROUS WATERS",
		"flavor": "积水如泥沼裹足，且怪物在潮湿环境中如鱼得水。",
		"flavor_en": "Stagnant waters drag your feet while beasts glide through unrestrained.",
		"description": "怪在水中不减速反增速；玩家涉水脚步声倍增",
		"desc_en": "Enemies gain speed in water; player wading footsteps double in volume",
		"icon": "water",
		"color": Color(0.85, 0.20, 0.55)
	},
	"curse_single_stone": {
		"id": "curse_single_stone",
		"name": "孤注一掷",
		"title_en": "LONE PEBBLE",
		"flavor": "深渊碎石稀缺，手中的诱饵只剩下最后一次机会。",
		"flavor_en": "Loose rocks are scarce in the deeper void.",
		"description": "每关可携带的投掷诱饵石数量上限降至 1 枚",
		"desc_en": "Max carried distraction pebbles reduced to 1 per sector",
		"icon": "pebble",
		"color": Color(0.92, 0.40, 0.35)
	},
	"curse_acoustic_decay": {
		"id": "curse_acoustic_decay",
		"name": "声纳衰减",
		"title_en": "ACOUSTIC DECAY",
		"flavor": "空气中弥漫的深渊粉尘急速吞噬声音的扩散。",
		"flavor_en": "Choking abyssal spores rapidly swallow traveling soundwaves.",
		"description": "玩家的发声与声纳回声探路有效半径削减 25%",
		"desc_en": "Player vocalization and sonar pulse propagation radius reduced by 25%",
		"icon": "wave_mute",
		"color": Color(0.78, 0.25, 0.70)
	},
	"curse_terror_shiver": {
		"id": "curse_terror_shiver",
		"name": "恐慌寒颤",
		"title_en": "TERROR SHIVER",
		"flavor": "被怪察觉的瞬间心跳失控，脚步难掩慌乱。",
		"flavor_en": "A pounding heartbeat betrays your position in the dark.",
		"description": "当有敌人处于警觉状态时，玩家脚步响度增加 50%",
		"desc_en": "Player footsteps produce 50% more sound when an enemy is alert",
		"icon": "heart_broken",
		"color": Color(1.0, 0.30, 0.60)
	},
	"curse_listener_feedback": {
		"id": "curse_listener_feedback",
		"name": "共鸣反噬",
		"title_en": "ACOUSTIC OVERLOAD",
		"flavor": "静默之耳吸收过量声波，即将引爆刺耳声啸。",
		"flavor_en": "Silent ears absorb resonance until exploding in a concussive burst.",
		"description": "Listener 累积 4 次声波后引发全图音爆短暂眩晕",
		"desc_en": "Listener beasts trigger a room-wide acoustic shock after 4 echoes",
		"icon": "bell",
		"color": Color(0.68, 0.20, 0.88)
	},
	"curse_predator_instinct": {
		"id": "curse_predator_instinct",
		"name": "近嗅感知",
		"title_en": "PREDATOR INSTINCT",
		"flavor": "掠食者的生物本能强化，即使静步也难逃逼近。",
		"flavor_en": "Close-range predatory senses sharpen dangerously.",
		"description": "敌人近身警戒范围扩大，贴身潜行更容易惊醒怪物",
		"desc_en": "Enemy proximity sensitivity increased; close sneaking alerts beasts",
		"icon": "eye",
		"color": Color(0.95, 0.30, 0.35)
	},
	"curse_fragile_breath": {
		"id": "curse_fragile_breath",
		"name": "幽闭气滞",
		"title_en": "STIFLED BREATH",
		"flavor": "深渊低氧环境压迫肺腑，连续发声变得极为吃力。",
		"flavor_en": "Thin, suffocating air exhausts the lungs after every shout.",
		"description": "发声按键的冷却充能时间增加 40%",
		"desc_en": "Vocalization recharge cooldown increased by 40%",
		"icon": "lungs",
		"color": Color(0.85, 0.35, 0.65)
	}
}

# --- 10 BOON REGISTRY (深渊馈赠) ---
const BOONS: Dictionary = {
	"boon_acoustic_amplifier": {
		"id": "boon_acoustic_amplifier",
		"name": "声标显形",
		"title_en": "ACOUSTIC MARK",
		"flavor": "发声波纹附着灵能微光，让黑暗中的威胁无所遁形。",
		"flavor_en": "Sonar waves coat lurkers with bioluminescent resonance.",
		"description": "声波波及怪物时为其附着 4 秒持续显形脉冲",
		"desc_en": "Enemies struck by soundwaves pulse with light for 4.0s",
		"icon": "sonar_mark",
		"color": Color(0.35, 0.88, 1.0)
	},
	"boon_water_strider": {
		"id": "boon_water_strider",
		"name": "水幕行者",
		"title_en": "WATER STRIDER",
		"flavor": "双足轻若浮萍，在深渊死水之上疾步如飞。",
		"flavor_en": "Lightfooted strides skim gracefully across dark underground water.",
		"description": "涉水移动不受任何减速，反获 +20% 移速加成",
		"desc_en": "Wading incurs no slowdown and grants +20% movement speed",
		"icon": "water_walk",
		"color": Color(0.30, 0.95, 0.80)
	},
	"boon_ricochet_pebble": {
		"id": "boon_ricochet_pebble",
		"name": "共振弹石",
		"title_en": "RICOCHET PEBBLE",
		"flavor": "特制的洞穴结晶碎石，落地后产生多重声响。",
		"flavor_en": "Crystalline cave stones bounce and click across rock.",
		"description": "投掷石落地后将再弹跳一次，连续引发两处声东击西",
		"desc_en": "Thrown pebbles bounce once more, triggering a secondary acoustic lure",
		"icon": "bounce",
		"color": Color(0.95, 0.85, 0.30)
	},
	"boon_phantom_tread": {
		"id": "boon_phantom_tread",
		"name": "幽影轻步",
		"title_en": "PHANTOM TREAD",
		"flavor": "脚步踏在虚空之中，静谧如穿梭暗影的潜行者。",
		"flavor_en": "Walking on silence like a ghost moving through the void.",
		"description": "潜行速度提升 25%，且潜行声音扩散范围缩小 50%",
		"desc_en": "Sneak speed increased by 25%; sneak sound radius reduced by 50%",
		"icon": "boot",
		"color": Color(0.40, 0.80, 1.0)
	},
	"boon_calm_breath": {
		"id": "boon_calm_breath",
		"name": "沉静屏息",
		"title_en": "CALM BREATH",
		"flavor": "心境彻底归于死寂，与冰冷的岩壁融为一体。",
		"flavor_en": "Standing still becomes indistinguishable from cold stone.",
		"description": "静止站立 1 秒进入屏息，敌人丢失搜索目标的判定加快 50%",
		"desc_en": "Standing still for 1s accelerates enemy search loss by 50%",
		"icon": "mask",
		"color": Color(0.50, 0.92, 0.85)
	},
	"boon_sonic_stagger": {
		"id": "boon_sonic_stagger",
		"name": "震荡音爆",
		"title_en": "SONIC SHOCKWAVE",
		"flavor": "全力释放的呼喊化作冲击气流，击退近身狂兽。",
		"flavor_en": "A full-throated call releases a concussive shockwave.",
		"description": "满蓄力发声时，震慑并击退 120px 内的近身怪 1.5 秒",
		"desc_en": "Fully-charged vocalization stuns and knocks back beasts within 120px for 1.5s",
		"icon": "shockwave",
		"color": Color(1.0, 0.78, 0.25)
	},
	"boon_deep_pockets": {
		"id": "boon_deep_pockets",
		"name": "巧手备弹",
		"title_en": "DEEP POCKETS",
		"flavor": "敏锐搜寻岩石间隙，总能在关键时刻摸出石子。",
		"flavor_en": "Keen eyes scour crevices for usable pebbles.",
		"description": "关卡初始石子 +1，踩中开关时额外补给 1 枚投掷石",
		"desc_en": "Start sector with +1 pebble; activating switches replenishes 1 pebble",
		"icon": "pouch",
		"color": Color(0.85, 0.90, 0.40)
	},
	"boon_wall_penetration": {
		"id": "boon_wall_penetration",
		"name": "透壁回声",
		"title_en": "PIERCING SONAR",
		"flavor": "超低频共振波轻易穿透坚硬石壁，直达出口。",
		"flavor_en": "Low-frequency resonance pulses effortlessly through dense rock.",
		"description": "声波穿透墙体感知门后空间，且出口光柱常态亮起",
		"desc_en": "Sonar waves penetrate walls, and the exit beacon remains permanently visible",
		"icon": "wall_pierce",
		"color": Color(0.45, 0.95, 0.70)
	},
	"boon_second_wind": {
		"id": "boon_second_wind",
		"name": "假死脱困",
		"title_en": "SECOND WIND",
		"flavor": "深渊幽灵赋予的绝处逢生，免于一次致命捕杀。",
		"flavor_en": "A phantom presence grants one miraculous escape from the jaw.",
		"description": "每关 1 次免死机会：受致命伤时震退怪物并获 3 秒神速",
		"desc_en": "Survive 1 fatal attack per sector: stuns beasts and grants 3.0s burst speed",
		"icon": "shield",
		"color": Color(0.95, 0.90, 0.55)
	},
	"boon_silent_stride": {
		"id": "boon_silent_stride",
		"name": "拟态软足",
		"title_en": "SILENT STRIDE",
		"flavor": "鞋底覆着柔软的苔藓微质，走动几不可闻。",
		"flavor_en": "Soft moss padding lines your boots, dampening your footsteps.",
		"description": "正常行走脚步声降低 35%，行走巡航更不易惊醒怪物",
		"desc_en": "Standard walking footstep sound reduced by 35%",
		"icon": "feather",
		"color": Color(0.60, 0.85, 1.0)
	}
}

# Active Loadout (Max 5 each)
var active_curses: Array[String] = []
var active_boons: Array[String] = []
var claimed_milestones: Dictionary = {} # int level -> { "curse": String, "boon": String }
var reroll_used_milestones: Dictionary = {} # int level -> bool


func _ready() -> void:
	load_modifiers_from_save()


func is_milestone_sector(level_num: int) -> bool:
	return MILESTONES.has(level_num)


func is_milestone_claimed(level_num: int) -> bool:
	return claimed_milestones.has(level_num)


func has_curse(curse_id: String) -> bool:
	return active_curses.has(curse_id)


func has_boon(boon_id: String) -> bool:
	return active_boons.has(boon_id)


# Returns candidates for a given milestone
func generate_pact_candidates(level_num: int) -> Dictionary:
	var seed_val := int(GameState.challenge_highest_unlocked * 137 + level_num * 31)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	# Unused curses pool
	var available_curses: Array[String] = []
	for cid in CURSES.keys():
		if not active_curses.has(cid):
			available_curses.append(cid)
	if available_curses.is_empty():
		available_curses = CURSES.keys().duplicate()
	available_curses.sort()
	var pick_c_idx := rng.randi_range(0, available_curses.size() - 1)
	var curse_id: String = available_curses[pick_c_idx]

	# Unused boons pool
	var available_boons: Array[String] = []
	for bid in BOONS.keys():
		if not active_boons.has(bid):
			available_boons.append(bid)
	if available_boons.is_empty():
		available_boons = BOONS.keys().duplicate()
	available_boons.sort()
	var pick_b_idx := rng.randi_range(0, available_boons.size() - 1)
	var boon_id: String = available_boons[pick_b_idx]

	return {
		"curse": CURSES[curse_id].duplicate(),
		"boon": BOONS[boon_id].duplicate()
	}


func reroll_single_item(is_curse: bool, current_id: String) -> Dictionary:
	var available: Array[String] = []
	var pool: Dictionary = CURSES if is_curse else BOONS
	var active_list: Array[String] = active_curses if is_curse else active_boons

	for k in pool.keys():
		if not active_list.has(k) and k != current_id:
			available.append(k)

	if available.is_empty():
		for k in pool.keys():
			if k != current_id:
				available.append(k)

	if available.is_empty():
		return pool[current_id].duplicate()

	available.shuffle()
	var new_id: String = available[0]
	return pool[new_id].duplicate()


func claim_pact(level_num: int, curse_id: String, boon_id: String) -> void:
	if not active_curses.has(curse_id):
		active_curses.append(curse_id)
	if not active_boons.has(boon_id):
		active_boons.append(boon_id)

	claimed_milestones[level_num] = {
		"curse": curse_id,
		"boon": boon_id
	}

	save_modifiers_to_save()
	pact_claimed.emit(level_num, curse_id, boon_id)
	modifiers_updated.emit()


func reset_challenge_run() -> void:
	active_curses.clear()
	active_boons.clear()
	claimed_milestones.clear()
	reroll_used_milestones.clear()
	save_modifiers_to_save()
	modifiers_updated.emit()


func save_modifiers_to_save() -> void:
	var cfg := ConfigFile.new()
	var save_path := "user://save_data.cfg"
	cfg.load(save_path)
	cfg.set_value("challenge_modifiers", "active_curses", active_curses)
	cfg.set_value("challenge_modifiers", "active_boons", active_boons)
	cfg.set_value("challenge_modifiers", "claimed_milestones", claimed_milestones)
	cfg.set_value("challenge_modifiers", "reroll_used_milestones", reroll_used_milestones)
	cfg.save(save_path)


func load_modifiers_from_save() -> void:
	var cfg := ConfigFile.new()
	var save_path := "user://save_data.cfg"
	if cfg.load(save_path) != OK:
		return
	active_curses = Array(cfg.get_value("challenge_modifiers", "active_curses", []), TYPE_STRING, &"", null)
	active_boons = Array(cfg.get_value("challenge_modifiers", "active_boons", []), TYPE_STRING, &"", null)
	claimed_milestones = cfg.get_value("challenge_modifiers", "claimed_milestones", {})
	reroll_used_milestones = cfg.get_value("challenge_modifiers", "reroll_used_milestones", {})
