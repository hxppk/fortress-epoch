class_name SkillResource
extends Resource
## SkillResource -- 技能基类
## 每个具体技能（主动/终极/被动）继承此类，实现 execute / can_execute / get_description。
## SkillSystem 通过 skill_id 动态加载对应脚本并调用。

# ============================================================
# 导出属性
# ============================================================

## 技能 ID（与 heroes.json 中的 id 对应）
@export var skill_id: String = ""

## 技能类型: "active" | "ultimate" | "passive"
@export var skill_type: String = "active"

## 冷却时间（秒，仅 active 技能使用）
@export var cooldown: float = 10.0

## 蓄力条件类型（终极技用）："kill_count" | "damage_dealt" | "skill_hit" | "pull_count"
@export var charge_type: String = ""

## 蓄力满值
@export var charge_max: float = 50.0

# ============================================================
# 虚方法 — 子类重写
# ============================================================

## 执行技能效果。
## caster: 施法者节点（HeroBase）
## stats: 施法者的 StatsComponent
## skill_system: 所属 SkillSystem 引用（用于访问工具方法）
func execute(caster: Node2D, stats: StatsComponent, skill_system: Node) -> void:
	pass


## 是否满足释放条件（子类可重写添加额外检查，如蓝量）
func can_execute(caster: Node2D, stats: StatsComponent) -> bool:
	return caster != null and stats != null and stats.is_alive()


## 获取技能描述文本
func get_description() -> String:
	return ""
