# 堡垒纪元 Fortress Epoch

**自走战斗 × 塔防建设 × Roguelike 卡牌**

Godot 4.6 | GDScript | 像素风 2D

---

## 游戏简介

堡垒纪元是一款融合了自走战斗、塔防建设和 Roguelike 卡牌元素的 2D 策略游戏。玩家操控英雄击退怪物浪潮，建造防御工事，通过卡牌选择强化阵容，并派遣远征队探索地下城。

## 当前版本：v0.3.0

### 核心玩法循环

```
教学 → 防守波次 → 波次结算 → 卡牌选择 → 建造准备 → 防守波次 → ... → 远征
```

每轮结束后进入卡牌选择，从 3 张随机卡牌中选 1 张永久强化。建造阶段可放置/升级防御建筑。每个阶段全部波次通关后可进入远征副本。

---

## 英雄（4 位）

| 英雄 | ID | 定位 | 普攻模式 | 被动技能 |
|------|-----|------|---------|---------|
| 白狼骑士 | `wolf_knight` | 近战战士 | 扇形横扫 | 嗜血本能（低血攻击加成 + 击杀回血） |
| 流星法师 | `meteor_mage` | AOE 法师 | 范围落点 | 星火燎原（命中附加灼烧 DOT） |
| 辉石法师 | `crystal_mage` | 技能爆发 | 单体弹射 | 辉石共鸣（技能后下次普攻 +60%） |
| 重力法师 | `gravity_mage` | 控制坦克 | 范围冲击 | 质量坍缩（周围敌人越多防御越高） |

每位英雄拥有 2 个主动技能 + 1 个终极技能 + 1 个被动。

## 建筑（4 种）

| 建筑 | ID | 功能 | NPC 单位 |
|------|-----|------|---------|
| 箭塔 | `arrow_tower` | 远程攻击敌人 | 弓箭手 |
| 金矿 | `gold_mine` | 持续产出金币 | 矿工 |
| 兵营 | `barracks` | 强化近战单位 | 骑士 |
| 铸造所 | `tech_forge` | 提升全队属性 | — |

同类建筑满 3 个后自动召唤 NPC 单位协助战斗。

## 卡牌系统（25 张）

| 类别 | 数量 | 示例 |
|------|------|------|
| 属性强化 | 5 | 攻击强化、生命强化、暴击直觉、全属性提升 |
| 技能强化 | 7 | 技能伤害+、冷却缩减、狼突增强、流星增强 |
| 资源类 | 5 | 击杀获金、自动产金、水晶矿脉、双倍掉落 |
| 装备类 | 5 | 烈焰之剑、寒霜盾牌、疾风之靴 |

装备卡带有槽位标识（武器/护甲/饰品），卡牌悬停 0.5 秒后显示效果预览。

## 波次系统（3 阶段 / 12 波）

| 阶段 | 波次数 | 敌人类型 | 英雄伤害系数 |
|------|--------|---------|------------|
| Stage 1 教学 | 2 | 史莱姆、哥布林 | 0.6 |
| Stage 2 | 5 | 骷髅、幽灵、僵尸、兽人精英 | 0.8 |
| Stage 3 | 5 | 骷髅骑士、暗影刺客、亡灵法师、BOSS | 1.0 |

敌人 HP 随波次递增，BOSS 波有特殊 HP 倍率。

## 远征系统（3 副本）

| 副本 | ID | 三阶段结构 |
|------|-----|-----------|
| 骷髅墓穴 | `skeleton_crypt` | 小怪 → 精英 → 城堡 |
| 兽人要塞 | `orc_fortress` | 小怪 → 精英 → 城堡 |
| 暗影神殿 | `shadow_temple` | 小怪 → 精英 → BOSS |

NPC 单位自动出征，三阶段逐步推进，通关获得奖励。

---

## 战斗系统

- **伤害公式**：`damage = max(ATK - DEF, 1)`，暴击 ×2
- **帧冻结**（Hitstop）：命中暂停 2 帧，暴击暂停 5 帧
- **击退**：普通命中 5px，暴击 10px + 随机角度偏移
- **连杀系统**：5/10/20/50/100 连杀触发屏幕提示
- **死亡特效**：粒子爆散 + 闪白 + 屏幕震动衰减

### 复活机制

- **英雄**：战斗中阵亡 → 10 秒后自动复活（扣堡垒 10% HP）
- **NPC 单位**：战斗中阵亡 → 本波不复活
- **新波次开始**：所有己方单位（英雄 + NPC）满血复活

---

## 项目架构

```
fortress_epoch/
├── data/                    # JSON 数据驱动配置
│   ├── heroes.json          # 英雄属性、技能、被动
│   ├── cards.json           # 卡牌效果定义
│   ├── buildings.json       # 建筑属性和升级数据
│   ├── waves.json           # 波次敌人配置
│   └── expeditions.json     # 远征副本结构
├── scenes/                  # Godot 场景文件
│   ├── main/                # 主场景 (game_session.tscn)
│   ├── entities/            # 英雄、敌人、NPC 场景
│   └── ui/                  # UI 面板场景
├── scripts/
│   ├── core/                # 核心系统
│   │   ├── game_session.gd  # 顶层协调器（委托子控制器）
│   │   ├── hero_controller.gd
│   │   ├── input_controller.gd
│   │   ├── npc_controller.gd
│   │   ├── ui_controller.gd
│   │   ├── phase_manager.gd # 阶段状态机
│   │   ├── wave_spawner.gd  # 波次生成
│   │   ├── game_manager.gd  # Autoload 全局状态
│   │   └── stats_component.gd
│   ├── combat/              # 战斗系统
│   │   ├── damage_system.gd # Autoload 伤害计算
│   │   ├── combat_feedback.gd # Autoload 战斗反馈
│   │   ├── skill_system.gd
│   │   ├── auto_attack.gd
│   │   └── skills/          # 技能脚本 (SkillResource)
│   ├── building/            # 建筑系统
│   ├── entities/            # 实体脚本 (hero_base, enemy_base, npc_base)
│   ├── roguelike/           # 卡牌系统
│   └── ui/                  # UI 脚本 (hud, card_ui)
└── assets/                  # 素材资源
```

### 设计模式

- **数据驱动**：所有英雄/卡牌/建筑/波次/远征通过 JSON 配置
- **组件化**：StatsComponent、AutoAttackComponent、SkillSystem 可组合
- **控制器分离**：GameSession 精简为协调层，逻辑分散到 4 个子控制器
- **对象池**：EnemyPool 预热 + 回收敌人实例
- **Autoload 单例**：GameManager、DamageSystem、CombatFeedback、BuildingManager、SaveManager

---

## 操作说明

| 按键 | 功能 |
|------|------|
| WASD | 移动英雄 |
| Q | 技能 1 |
| E | 技能 2 |
| R | 终极技能 |
| 1 / 2 / 3 | 快捷建造 箭塔 / 金矿 / 兵营 |
| ESC | 取消建造 / 暂停 |

---

## 版本历史

- **v0.3.0** — 新英雄 (crystal_mage, gravity_mage)、卡牌扩展至 25 张、装备卡、3 阶段波次、远征三段式、GameSession 重构、战斗反馈 (hitstop/击退/连杀)、英雄血条与复活机制
- **v0.2.3** — 单人打磨：暂停菜单、新手引导、统一伤害系统、被动技能、数值调优
- **v0.2.1** — 远征战斗、NPC 系统、局外成长
