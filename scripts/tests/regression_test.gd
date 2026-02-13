extends SceneTree
## 核心流程回归测试 — 无需场景加载，纯逻辑验证
## 用法: godot --headless --script res://scripts/tests/regression_test.gd

var passed: int = 0
var failed: int = 0
var test_results: Array = []


func _init() -> void:
	print("=" .repeat(60))
	print("  回归测试 v0.2.1")
	print("=" .repeat(60))

	test_resource_operations()
	test_stats_component_logic()
	test_evil_castle_hp_formula()
	test_npc_limit_logic()
	test_phase_order()
	test_meta_progression()
	test_save_data_format()

	_print_report()
	quit()


# ============================================================
# 测试辅助
# ============================================================

func assert_eq(actual: Variant, expected: Variant, test_name: String) -> void:
	if actual == expected:
		passed += 1
		test_results.append("  PASS: %s" % test_name)
	else:
		failed += 1
		test_results.append("  FAIL: %s (期望 %s, 实际 %s)" % [test_name, str(expected), str(actual)])


func assert_true(condition: bool, test_name: String) -> void:
	assert_eq(condition, true, test_name)


func assert_false(condition: bool, test_name: String) -> void:
	assert_eq(condition, false, test_name)


# ============================================================
# 测试: GameManager 资源增减
# ============================================================

func test_resource_operations() -> void:
	print("\n--- 测试: 资源操作 ---")

	# 模拟资源操作（不依赖 autoload，直接测试逻辑）
	var resources: Dictionary = {"gold": 100, "crystal": 0, "badge": 0, "exp": 0}

	# 增加金币
	resources["gold"] += 50
	assert_eq(resources["gold"], 150, "增加 50 金币后 = 150")

	# 消耗金币
	var cost: int = 50
	if resources["gold"] >= cost:
		resources["gold"] -= cost
	assert_eq(resources["gold"], 100, "消耗 50 金币后 = 100")

	# 余额不足
	var can_spend: bool = resources["gold"] >= 200
	assert_false(can_spend, "100 金不足以消耗 200")

	# crystal 初始为 0
	assert_eq(resources["crystal"], 0, "crystal 初始 = 0")

	# badge 初始为 0
	assert_eq(resources["badge"], 0, "badge 初始 = 0")


# ============================================================
# 测试: StatsComponent 属性计算逻辑
# ============================================================

func test_stats_component_logic() -> void:
	print("\n--- 测试: 属性计算逻辑 ---")

	# 模拟 StatsComponent 的 modifier 系统
	var base_stats: Dictionary = {"attack": 30.0, "defense": 5.0, "hp": 120.0}
	var modifiers: Dictionary = {"attack": {}, "defense": {}, "hp": {}}

	# 添加 modifier
	modifiers["attack"]["card_buff"] = 10.0
	var total_attack: float = base_stats["attack"]
	for mod_val: float in modifiers["attack"].values():
		total_attack += mod_val
	assert_eq(total_attack, 40.0, "attack 30 + card_buff 10 = 40")

	# 添加第二个 modifier
	modifiers["attack"]["last_stand"] = 6.0
	total_attack = base_stats["attack"]
	for mod_val: float in modifiers["attack"].values():
		total_attack += mod_val
	assert_eq(total_attack, 46.0, "attack 30 + 10 + 6 = 46")

	# 移除 modifier
	modifiers["attack"].erase("card_buff")
	total_attack = base_stats["attack"]
	for mod_val: float in modifiers["attack"].values():
		total_attack += mod_val
	assert_eq(total_attack, 36.0, "移除 card_buff 后 attack = 36")


# ============================================================
# 测试: 邪恶城堡 HP 公式
# ============================================================

func test_evil_castle_hp_formula() -> void:
	print("\n--- 测试: 邪恶城堡 HP 公式 ---")

	# 公式: total_dps * 30.0 * 3.0
	var total_dps: float = 16.0  # 1个箭塔 NPC DPS (16 damage / 1.0s)
	var castle_hp: float = total_dps * 30.0 * 3.0
	assert_eq(castle_hp, 1440.0, "单箭塔 DPS=16 → 城堡HP=1440")

	# 多 NPC
	total_dps = 16.0 + 30.0 + 14.4  # archer + knight(Lv1) + miner(Lv1)
	castle_hp = total_dps * 30.0 * 3.0
	# 60.4 * 90 = 5436
	assert_eq(castle_hp, 60.4 * 30.0 * 3.0, "三种 NPC 总DPS=60.4 → 城堡HP=5436")

	# 0 DPS → 0 HP
	castle_hp = 0.0 * 30.0 * 3.0
	assert_eq(castle_hp, 0.0, "0 DPS → 城堡HP=0")


# ============================================================
# 测试: NPC 上限逻辑
# ============================================================

func test_npc_limit_logic() -> void:
	print("\n--- 测试: NPC 上限检查 ---")

	# 模拟已有 NPC 列表
	var existing_npcs: Array = [
		{"type": "archer"},
		{"type": "knight"},
	]

	# 检查 archer 是否已存在
	var should_skip_archer: bool = false
	for npc: Dictionary in existing_npcs:
		if npc["type"] == "archer":
			should_skip_archer = true
			break
	assert_true(should_skip_archer, "archer 已存在，应跳过")

	# 检查 miner 是否已存在
	var should_skip_miner: bool = false
	for npc: Dictionary in existing_npcs:
		if npc["type"] == "miner":
			should_skip_miner = true
			break
	assert_false(should_skip_miner, "miner 不存在，应生成")

	# 生成 miner 后再检查
	existing_npcs.append({"type": "miner"})
	should_skip_miner = false
	for npc: Dictionary in existing_npcs:
		if npc["type"] == "miner":
			should_skip_miner = true
			break
	assert_true(should_skip_miner, "miner 已存在，应跳过")

	# building_type → npc_type 映射
	var mapping: Dictionary = {
		"arrow_tower": "archer",
		"barracks": "knight",
		"gold_mine": "miner",
	}
	assert_eq(mapping["arrow_tower"], "archer", "arrow_tower → archer")
	assert_eq(mapping["barracks"], "knight", "barracks → knight")
	assert_eq(mapping["gold_mine"], "miner", "gold_mine → miner")


# ============================================================
# 测试: PhaseManager 阶段转换顺序
# ============================================================

func test_phase_order() -> void:
	print("\n--- 测试: 阶段转换顺序 ---")

	# 正常流程: tutorial → prepare → defend → wave_clear → [expedition] → prepare → ...
	var valid_transitions: Dictionary = {
		"tutorial": ["prepare", "wave_clear"],
		"prepare": ["defend"],
		"defend": ["wave_clear", "boss"],
		"wave_clear": ["expedition", "card_selection", "prepare"],
		"card_selection": ["prepare"],
		"expedition": ["prepare", "card_selection"],
		"boss": ["wave_clear", "victory"],
		"victory": [],
		"defeat": [],
	}

	# 验证合法转换
	assert_true("prepare" in valid_transitions["tutorial"], "tutorial → prepare 合法")
	assert_true("defend" in valid_transitions["prepare"], "prepare → defend 合法")
	assert_true("wave_clear" in valid_transitions["defend"], "defend → wave_clear 合法")
	assert_true("expedition" in valid_transitions["wave_clear"], "wave_clear → expedition 合法")
	assert_true("prepare" in valid_transitions["expedition"], "expedition → prepare 合法")

	# transition 阶段（已标记为辅助过渡，实际由 expedition 替代）
	assert_true(not valid_transitions.has("transition"), "transition 不在主流程中")


# ============================================================
# 测试: MetaProgression 数据结构
# ============================================================

func test_meta_progression() -> void:
	print("\n--- 测试: 局外成长数据 ---")

	var prog := MetaProgression.new()

	# 默认数据
	assert_eq(prog.data["version"], 1, "存档版本 = 1")
	assert_eq(prog.data["currencies"]["crystal"], 0, "初始 crystal = 0")
	assert_eq(prog.data["currencies"]["badge"], 0, "初始 badge = 0")
	assert_eq(prog.get_hero_level("wolf_knight"), 1, "wolf_knight 初始 Lv1")

	# 添加货币
	prog.add_currency("crystal", 10)
	assert_eq(prog.get_currency("crystal"), 10, "添加 10 crystal 后 = 10")

	# 消耗货币
	var ok: bool = prog.spend_currency("crystal", 5)
	assert_true(ok, "消耗 5 crystal 成功")
	assert_eq(prog.get_currency("crystal"), 5, "消耗后 crystal = 5")

	# 余额不足
	ok = prog.spend_currency("crystal", 100)
	assert_false(ok, "crystal 不足 100 消耗失败")
	assert_eq(prog.get_currency("crystal"), 5, "失败后 crystal 不变 = 5")

	# 记录游戏
	prog.record_game(true, 50, 5, 120.0)
	assert_eq(prog.data["stats"]["total_games"], 1, "总局数 = 1")
	assert_eq(prog.data["stats"]["total_wins"], 1, "总胜场 = 1")
	assert_eq(prog.data["stats"]["total_kills"], 50, "总击杀 = 50")
	assert_eq(prog.data["stats"]["best_wave"], 5, "最高波次 = 5")

	# 英雄经验
	prog.add_hero_exp("wolf_knight", 50)
	assert_eq(prog.get_hero_level("wolf_knight"), 2, "50 exp → wolf_knight Lv2")

	prog.add_hero_exp("wolf_knight", 70)
	assert_eq(prog.get_hero_level("wolf_knight"), 3, "再加 70 exp (总120) → wolf_knight Lv3")


# ============================================================
# 测试: 存档数据格式
# ============================================================

func test_save_data_format() -> void:
	print("\n--- 测试: 存档数据格式 ---")

	var default_data: Dictionary = MetaProgression.get_default_data()

	# 检查顶级 key
	assert_true(default_data.has("version"), "存档有 version 字段")
	assert_true(default_data.has("stats"), "存档有 stats 字段")
	assert_true(default_data.has("currencies"), "存档有 currencies 字段")
	assert_true(default_data.has("hero_progress"), "存档有 hero_progress 字段")
	assert_true(default_data.has("research"), "存档有 research 字段")
	assert_true(default_data.has("unlocks"), "存档有 unlocks 字段")

	# 检查 unlocks 默认值
	var unlocks: Dictionary = default_data["unlocks"]
	assert_true("wolf_knight" in unlocks["heroes"], "默认解锁 wolf_knight")
	assert_eq(unlocks["buildings"].size(), 3, "默认解锁 3 种建筑")

	# JSON 序列化/反序列化验证
	var json_str: String = JSON.stringify(default_data)
	var json := JSON.new()
	var err: int = json.parse(json_str)
	assert_eq(err, OK, "存档数据可正确 JSON 序列化/反序列化")


# ============================================================
# 报告
# ============================================================

func _print_report() -> void:
	print("\n" + "=" .repeat(60))
	print("  测试结果: %d 通过, %d 失败 (共 %d)" % [passed, failed, passed + failed])
	print("=" .repeat(60))
	for r: String in test_results:
		print(r)
	print("")

	if failed > 0:
		print("  *** 存在失败项! ***\n")
	else:
		print("  全部通过!\n")
