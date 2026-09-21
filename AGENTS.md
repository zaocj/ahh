# AGENTS.md

给在这个 Godot 项目里工作的 AI 编码工具（Claude Code / Codex / Cursor / pi 等）看的说明。
目的：**改对地方、不踩已知坑**。人读也适用。

## 项目速览

- 引擎：**Godot 4.7.x**（当前 4.7.2-stable），纯 **2D** 俯视，观感偏 "2.5D"（靠 y-sort 做前后遮挡）
- 目标形态：类《荒野乱斗》的多人竞技 —— 英雄 + 技能 + 竞技场
- 渲染：`renderer/rendering_method = "mobile"`；已开 `textures/vram_compression/import_etc2_astc = true`（Android 导出硬要求）
- 主场景：`res://main/main.tscn`
- 拉伸：`canvas_items` + `expand` → **UI 必须用锚点**，不要写死像素坐标
- 目录约定：**按功能垂直切分**。一个功能的脚本 / 场景 / 数据放同一目录，不要按文件类型分成 `scripts/` + `scenes/`

## 目录结构

| 路径 | 放什么 | 现状 |
|---|---|---|
| `addons/godot_agent_loop/` | 编辑器插件（MCP 桥，`@tool extends EditorPlugin`）。**只在编辑器里跑**，导出预设已把它排除 | 有内容 |
| `addons/godot_ability_system/` | **技能系统插件（git 子模块**，MIT，pin 在 `a360f40`，[LiGameAcademy/godot_ability_system](https://github.com/LiGameAcademy/godot_ability_system)）。技能定义/特性/冷却/行为树/属性/血条 vital/效果/状态/标签/伤害计算都在这里。**不要改子模块里的文件**（升级会冲突），要扩展就在 `skills/two_d/` 里继承它的类。它是**3D-first**的（见下方"技能系统"） | 有内容（子模块） |
| `assets/textures/` | 共享原始素材。现有 `terrain_atlas.png` = 程序化生成的 4 格图集（地面 / 地面变体 / 墙 / 地台） | 有内容 |
| `assets/audio/` | 占位音效（`hit` / `player_hit` / `shoot` / `dash` / `death` / `win` / `lose` / `tick`，8 个短 wav，**程序化合成的占位**，直接换文件即可）。`assets/fonts/` 仍空 | 有内容 |
| `core/battle/` | 战斗编排：`match_director.gd`（3v3 流程：spawn → READY → PLAYING → **OVERTIME** → FINISHED，按队伍数存活人数判定，见“3v3 对局”）、`teams.gd`（敌我判定）、`match_stats.gd`（击杀/伤害计分）、`team_roster.gd` + `heroes/roster.tres`（谁上场）、`spawn_layout.gd` + `maps/arena_01/spawns.tres`（出生点数据）、`match_config.gd`（选人界面传给对局场景的静态持有者） | 有内容 |
| `core/network/` | 联网（同步、房间、消息） | 空（占位） |
| `core/events/` | 全局事件总线（autoload `CombatEvents`）。`combat_events.gd`（autoload `CombatEvents`：`damaged` / `died` / `ability_cast` / `match_finished`）。**玩法只 report，表现只 subscribe**（见下方“命中反馈”） | 有内容 |
| `core/utils/` | 跨功能工具函数。现有 `targets.gd`（`Targets.nearest()` / `offset_to_nearest()`：按 group 找最近目标，技能自动瞄准与敌人追击共用） | 有内容 |
| `entities/base/` | **可复用战斗单位**：`unit.gd` + `unit.tscn` + `unit_shape.tres` + `unit_camera.gd`。**一份预制被 3v3 的每个座位实例化 6 次**（原来是 `entities/player/` + `entities/enemy/` 两份，2026-09 已合并），队伍/操作者（人 / AI）/英雄都是数据（`team` / `controller` / `hero`）。`unit_camera.gd` 是*全队共用的一台相机*（跟着本地玩家，死后跟队友），不是每个单位一台 | 有内容 |
| `entities/player/` | **玩家**：`player.gd` + `player.tscn` + `player_shape.tres`（`facing` / `dash()` / `is_dashing()`，group `players`） | 有内容 |
| `entities/projectile/` | **投射物**：`projectile.gd` + `projectile.tscn` + `projectile_shape.tres`（匀速直飞，撞墙/打到实体/飞满 `max_distance` 自毁） | 有内容 |
| `heroes/<hero>/` | **一个英雄一个目录**，里面只有数据：`<hero>_data.tres`（`HeroData`：显示名 / 颜色 / 描述 / 签名技能名 / `loadout` / `stats`）。5 个英雄 = 原来的 5 个技能（`gunner` Shot、`frost` Frost、`bomber` Bomb、`sigil` Sigil、`medic` Heal），每人再加一个通用 `dash`。英雄**不是**预制也不是脚本：单位预制共用，英雄只是数据（`heroes/base/hero_data.gd`）。`heroes/roster.tres`（`TeamRoster`）决定哪 3 个上蓝队 / 红队、以及选人界面展示哪 5 个 | 有内容 |
| `entities/hitbox/` | 命中判定盒 | 空（占位） |
| `entities/pickup/` | 拾取物（能量块、补给） | 空（占位） |
| `core/battle/teams.gd` | **唯一的敌我判定**（`Teams.Id` / `is_hostile` / `can_damage` / `group_of` / `enemy_group_of` / `color_of`）。投射物与法阵都问它，技能数据里不再手填 `target_group` | 有内容 |

| `skills/two_d/` | **插件的 2D 适配层**（插件本体在 3D 侧，2D 项目必须自己补）：`indicator_preview_2d.gd`（2D 瞄准指示器 + 默认朝向）、`ability_node_spawn_projectile_2d.gd`（行为树节点：发射 2D 投射物）、`projectile_data_2d.gd`、`ge_dash_2d.gd`（2D 位移效果）、`flat_damage_logic.gd`（固定伤害策略）、`ability_input_router.gd`（按钮 → 插件生命周期，玩家用）、`ai_ability_router.gd`（AI → 插件生命周期，敌人用）、`ability_loadout_2d.gd` / `stat_block_2d.gd`（把数组型配置塞进 `.tres`）、`skill_indicator.gd` + `skill_indicator_data.gd`（2D 指示器绘制） | 有内容 |
| `skills/data/shared/tags/` | 项目的**标签词表**（`GameplayTag` 资源：`status.frozen` / `state.frozen` …）。插件 TagManager 只认得被注册过的标签，未注册的 `add_tag` 会警告并静默失败 → `main.gd` 启动时 `TagManager.initialize("res://skills/data/shared/tags/")`。**故意不带 `parent_tag_id`**，见坑 17 | 有内容 |
| `skills/data/enemy/<skill>/` | **敌人技能数据**（和玩家技能同一套格式，但**不配预览策略**）：`bolt.tres`（ProjectileData2D，`target_group = players`）+ `bolt_skill.tres`；`skills/data/enemy/loadout.tres` 是敌人的技能栏 | 有内容（`bolt/`） |
| `skills/data/shared/` | 跨技能共用数据：属性（`max_health`…）、`vitals/health.tres`、`enemy_stats.tres`（属性集 + vital）、`effects/bullet_damage.tres`（GE_ApplyDamage + 固定 10） | 有内容 |
| `skills/data/player/<skill>/` | **一个技能一个目录**：`<skill>.tres`（GameplayAbilityDefinition：特性 + 行为树 + 预览策略）、`preview.tres`、`indicator.tres`、以及该技能的子弹数据 | 有内容（`shot/`、`dash/`、`loadout.tres`） |
| `skills/data/build/` | `generate_ability_data.gd/.tscn`：一键生成上面这些 `.tres`（嵌套资源手写易错）。**只在加/改技能结构时跑一次**，之后在编辑器里改 `.tres` | 有内容 |
| `maps/arena_01/` | **一张地图一个目录**：`arena_01.tscn`（根 `Arena01` + 子 `Terrain` TileMapLayer）、`arena_01_tileset.tres`、`terrain.gd`（按 ASCII 地图刷格） | 有内容 |
| `ui/hud/` | 局内 HUD。现有 `virtual_joystick.gd`（触摸/鼠标摇杆）、`skill_button.gd`（技能按钮：短按直接施放，长按/拖动瞄准） | 有内容 |
| `ui/battle/` | 对局内界面与反馈。现有 `result_overlay.gd/.tscn`（结算面板：标题 + 原因 + Rematch；`PROCESS_MODE_ALWAYS`，因为在世界暂停时也要能点）、`damage_number.gd/.tscn` + `damage_numbers.gd`（伤害飘字与其订阅者）、`combat_sfx.gd`（音效订阅者 + 声音池） | 有内容 |
| `tests/` | **回归断言套件（受版本管理）**：`verify_match.gd/.tscn`（37 条对局闭环）、`verify_indicator.gd/.tscn`（30 条指示器/瞄准/多施法者）、`verify_feedback.gd/.tscn`（19 条飘字/闪白/震屏/音效）、`verify_grenade.gd/.tscn`（18 条手雷）、`shots_grenade.gd/.tscn`（截图脚本）、`run.sh`（一键跑全部）。**这是唯一一个破例新增的顶层目录**——以前这类套件放在 `.godot/` 里，被 gitignore 且会被缓存清理删掉（原 32 条套件就是这样丢了） | 有内容 |
| `ui/lobby/` | **开始界面**（`lobby.tscn/.gd`）：标题 + 赛制说明 + START → 选人界面。**它是 `project.godot` 的 main scene** | 有内容 |
| `ui/hero_select/` | **选人界面**（`hero_select.tscn/.gd` 根 + `hero_cards.gd` 五张卡）：点卡片选中、START MATCH 开始 3v3；选择通过 `MatchConfig.selected_hero` 传给对局场景 | 有内容 |
| `main/` | **装配根**：`main.tscn` + `main.gd`（实例化玩家与地图、接线摇杆、HUD 状态） | 有内容 |
| 根目录 | `project.godot`（输入映射 / 主场景 / 渲染设置）、`export_presets.cfg`（Android 预设）、`icon.svg`、`.vscode/` | — |

### 空目录 = 约定占位

空目录表示**领域边界已定、内容还没写**。新功能请放进对应目录，不要另造平级目录（例如别新建 `weapons/`，武器是 `entities/projectile/` 或 `skills/` 的事）。
注意：git 不跟踪空目录 —— 目录里有第一个真实文件后才会被提交。

## 现有内容怎么协作

```
ui/lobby/lobby.tscn  Lobby (Control)      ← project.godot 的 main scene：START
  └─ START → ui/hero_select/hero_select.tscn  HeroSelect
       ├─ Cards  (HeroCards：5 张英雄卡，程序化绘制 + 命中测试)
       ├─ Start  (ActionButton) → MatchConfig.selected_hero = 选中英雄 → change_scene
       └─ Back   → 回大厅

main/main.tscn        Main (Node2D, y_sort_enabled)
                      ├── HUD (CanvasLayer) → Status (左下提示) + Timer (局中时钟) + Score (存活人数 "3 : 3")
                      │                    → Announce (3-2-1-GO / +30s OVERTIME) + ResultOverlay (结算+计分板)
                      │                    → Joystick (virtual_joystick.gd) + SkillBullet / SkillDash (skill_button.gd)
                      ├── Arena01  ← maps/arena_01/arena_01.tscn → Terrain (TileMapLayer, z_index -10)
                      ├── Camera   (UnitCamera：全场唯一相机，跟 `MatchDirector.watched_unit`)
                      ├── MatchDirector (core/battle/match_director.gd)  ← 生成 6 个单位、跑流程、计分
                      ├── DamageNumbers (ui/battle/damage_numbers.gd：飘字订阅者)
                      └── CombatSfx     (ui/battle/combat_sfx.gd：音效订阅者)

运行时由 MatchDirector 生成（`entities/base/unit.tscn` × 6，`get_parent().add_child`）：
  Player    蓝队 0 号位 = 本地玩家（人控，带 InputRouter）
  BlueBot1/2  蓝队 AI 队友（带 AiRouter）
  RedBot0/1/2 红队 AI（带 AiRouter）
```

- **3v3 对局**（`MatchDirector`）：3 人 vs 3 人、**不复活**；1 分钟到 → **存活人数多的一方胜**；人数相同 → **加时 30s**，加时里**先掉人的一方输**，加时结束仍相同 → 平局；任意时刻一方被团灭立即结束。`READY` / `FINISHED` 用 `get_tree().paused` 冻结世界（director 自己 `PROCESS_MODE_ALWAYS`），所以**不需要任何锁输入代码**。
  本地玩家阵亡**不会**结束对局（队友还在），相机自动切到活着的队友（`spectate_changed` → `main.gd` 把 `UnitCamera.follow` 换人）；全队阵亡 = 输。
- **团队与敌我**：每个单位有 `team`（`Teams.Id.BLUE / RED`）并加入 `team_blue` / `team_red`（本地玩家额外加入 `players`，相机/HUD/"我被打了"的音效靠它）。**谁能打谁只有一处规则**：`Teams.can_damage(source, target)`（投射物、法阵、AI 目标搜索都问它）——技能数据里的 `target_group` 只是"没有队伍归属的来源"（地形、测试）的兜底。
- **单位**（`entities/base/unit.gd`）：移动（键盘/摇杆 或 AI 追击）、`dash()`、`facing`、血条（队伍色）、闪白、冻结（`is_frozen()`）、死亡（停止碰撞 + 退出队伍 group，但**节点保留**，因为计分板和相机还引用它）。`controller = HUMAN/AI` 决定移动来源；`hero` 决定外观/属性/技能栏。
- **英雄**：`HeroData` 资源（数据，不是脚本/预制）。`loadout.abilities = [签名技能, dash]`。选人界面把选择写进 `MatchConfig.selected_hero`，`MatchDirector._spawn_units()` 用它替换蓝队 0 号位；没有选择时（测试、直接 F5）用 `heroes/roster.tres` 里 `blue[0]`。**加一个英雄 = 在 `generate_ability_data.gd` 的 `_generate_heroes()` 里加一行 + 加进 `selectable`**，跑一次生成器。
- **出生点**：`maps/arena_01/spawns.tres`（`SpawnLayout`）由生成器**从竞技场 ASCII 地图里自动挑可走格**（左右两侧各 3 个，按高度分散），所以改地图后重跑生成器即可；`tests/verify_3v3.gd` 断言每个点都在地板格上。
- **计分板**：`MatchStats`（`core/battle/`）订阅 `CombatEvents` 记每人的击杀与伤害（按队伍过滤，友伤不计），`ui/battle/result_overlay.gd` 渲染成 HERO / KILLS / DAMAGE 三列 + 队伍色块 + `(you)` + `- down`。

- **对局流程**（`MatchDirector`，`core/battle/`）：`READY`（3-2-1-GO，`get_tree().paused = true` 冻结世界 → 期间**不需要**任何“锁输入”代码）→ `PLAYING`（60s 计时）→ `FINISHED`（再次暂停，发 `finished`，`ui/battle/result_overlay.tscn` 弹出，Rematch 走 `director.restart()` → `reload_current_scene()`）。
  胜负：**玩家阵亡 → 敌方胜**；**敌人全灭 → 玩家胜**；同一帧双方都死 → 平局；**60s 到 → 比剩余血量比例**（玩家 vs 敌人平均，差值 ≤5% 算平局）。玩家死亡**不销毁节点**（相机挂在玩家身上），只是变灰、停手、`is_alive()` 变 false。
  `MatchDirector` 是 `PROCESS_MODE_ALWAYS`（它自己就是暂停/解暂停的那个节点），其余节点保持默认（可暂停）——所以新加的东西默认就会被 READY/FINISHED 冻结，不需要额外配合。
- **敌人也会用技能**：和玩家同一条插件链路，只是入口换成 `AiAbilityRouter`（`skills/two_d/`）——它只看“冷却好了 + 目标在 `cast_range` 内 + 没被沉默”，就用 `try_activate_ability(id, {target_direction, targets})` 施放。技能数据在 `skills/data/enemy/`，**没有预览策略**（AI 不用指示器瞄准，也就不会碰到“一份 definition 共享一个 preview_strategy”的坑，见坑 15）。
  敌人子弹的 `ProjectileData2D.target_group = players`：Area2D 分不清敌我，**阵营靠 group 过滤**（`projectile.gd`），所以敌人不会误伤同类。
  `AiAbilityRouter.silence_statuses = [&"frozen"]` → 被冻住的施法者不能开火：这就是 frost 技能对敌人的实际价值。

- **输入**：`project.godot` 里 4 个命名 action（`move_left/right/up/down`，WASD + 方向键）。`player.gd` 用 `Input.get_vector()` 读它们，摇杆则通过 `player.joystick_input` 汇入同一入口。→ 加新操作请加命名 action，不要用 `ui_*`。
- **玩家视觉**：`Player/Body` 是 `Polygon2D`，颜色即"有色方块"。换成正式 Sprite 时删掉 `player.gd` 里推导多边形的代码即可。
- **技能**：由插件驱动，一条链路是
  `HUD 按钮 → AbilityInputRouter.press/drag/release → GameplayAbilityComponent.request_ability_preview() / update_targeting() / confirm_targeting() / try_activate_ability()`。
  **按下**就进预览（指示器立刻出现，响应快），**拖动**超过 `aim_dead_zone` 才覆盖默认朝向，**松手**用 `confirm_targeting()` 的结果施放；所以"点一下"永远走技能的默认方向。冷却、消耗、执行全部在插件里（`CooldownFeature` / `CommitCooldown` 节点 / 行为树）；按钮的扇形遮罩读 `CooldownFeature.get_cooldown_progress()`（`main.gd::_process` 每帧同步）。
- **两种瞄准模式**（`IndicatorPreview2D.targeting`）：`DIRECTION`（箭矢/子弹：只用拖动的**角度**，效果飞到 `max_range`；点一下 = 自动瞄准最近敌人）和 `POSITION`（投掷/选址类，如手雷：拖动的**长度**就是投掷距离 —— `full_drag_pixels` 像素 = 满距离 —— 另配 `range_indicator_data` 画一圈"射程环"，落点被夹在环内；点一下 = 直接落在最近目标身上）。做 POSITION 技能时行为树节点要写 `target_position_key = "target_position"`（`AbilityNodeSpawnProjectile2D` 会按落点反算方向和距离）。
- **默认朝向（自动瞄准）**在 `IndicatorPreview2D.default_aim` 上：`FACING` / `TO_TARGET`（朝 `target_group` 里最近目标）/ `AWAY_FROM_TARGET`（反向，后撤 dash）。当前 `shot` = `TO_TARGET`、`dash` = `AWAY_FROM_TARGET`，`target_group` 都是 `enemies`（敌人预制已加入该 group）。没有目标时回退 `facing`。
- **预览策略的归属**：`.tres` 里的 `preview_strategy` 是每个*定义*一份（不是每个施法者一份），所以两个 router 都会用 `AbilityLoadout2D.private_definition()` 给每个 caster 一份副本。新增技能时不用管这件事；但**不要自己把 `.tres` 里的 strategy 直接 `learn_ability` 给某个实体**（会和其他施法者抢同一个指示器，见坑 21）。
- **施放结果怎么传到行为树**：预览策略的 `get_result_context()` 返回 `target_direction`（Vector2）/ `target_position`，插件把它作为 context 交给行为树；`AbilityNodeSpawnProjectile2D` 读 `target_direction`，`GE_Dash2D` 也读它。**context 里必须始终带一个 `targets` 数组**（哪怕为空）——见坑 10。
- **加一个新技能**：先在 `skills/data/build/generate_ability_data.gd` 里照着现有段落拼出来（特性 + 行为树 + 预览策略），跑一次 `generate_ability_data.tscn` 生成 `.tres`，把它加进 `skills/data/player/loadout.tres`，再在 `main.tscn` 的 HUD 里加一个 `SkillButton`（顺序 = 槽位顺序）。之后数值都在编辑器里改 `.tres`。**不要给技能写专门的脚本**：优先用插件的特性 + 行为树节点 + 效果组合。
- **加一个敌人技能**：同上，但 loadout 换成 `skills/data/enemy/loadout.tres`、**不要配 `preview_strategy`**（AI 靠 `target_direction` 施放），伤害放到 `skills/data/shared/effects/`，投射物数据记得写 `target_group`。敌人的 `AiRouter` 会自动把它加进 `learn_ability`（技能栏在 `loadout.tres` 里）。
- **命中反馈（P1 手感）**：链是 `玩法 report → CombatEvents(autoload) → 各表现订阅者`。
  - 上报点：`Player` / `Enemy` 通过 **vital 自己的 `damage_applied` / `health_depleted`** 上报（这两个信号带准确数值；组件的 `vital_value_changed` 只说明"现在是多少"，用来刷新血条/闪白）；两个 router 施放成功时 `report_cast`；`MatchDirector._finish()` 冻结世界后 `report_match_finished`。
  - 订阅点：`DamageNumbers`（飘字，`damage_number.tscn`，玩家红/敌人黄，上升淡出自毁）、`CombatSfx`（8 个音效 + 6 路声音池 + 音高抖动；`play_history()` 记录"要过哪些声音"，因为 `playing` 太短命，headless 下更不可信）、`Player/Camera`（`player_camera.gd`：trauma 式震屏，`offset` 用正弦叠加而不是逐帧随机，衰减到 0 时精确归零）。
  - 加新反馈 = 加一个订阅者，**不要**在实体/技能里写"播个音效/弹个数字"。
  - 倒计时"嘟嘟"声是**对局流程**反馈而不是战斗事件，所以由 `main.gd` 直接从 `director.announce` 接到 `CombatSfx.play_announce()`。
- **伤害路径**：投射物不改血量，它带一串插件 `GameplayEffect`（`payload_effects`，来自 `ProjectileData2D`），命中时 `effect.apply(target, instigator, context)` → `GE_ApplyDamage` → `DamageCalculator`（这里配的是 `FlatDamageLogic` 固定 10）→ 目标的 `GameplayVitalAttributeComponent` → `HealthVital.apply_damage()`。所以**可被打 = 有 `GameplayVitalAttributeComponent` 节点**（投射物用这个名字判断，墙/地形直接被跳过）。伤害数值只写在 `skills/data/shared/effects/*.tres` 与 `flat_damage_10.tres` 里。
- **实体约定**：`facing`（朝向）、`dash(direction, distance, duration)`（可位移，由 `GE_Dash2D` 调用）、group `players`（可被追）/ `enemies`（可被瞄准）、`get_gameplay_ability_component()`（插件查组件的接口，见 player.gd）。血量/属性不写在实体脚本里，挂在插件组件上。
- **地形**：`maps/arena_01/terrain.gd` 的 `ARENA` 常量（每格一字符：`#` 墙、`.` 地面、`o` 地台）在 `_ready()` 里 `set_cell` 刷出来。只有**墙格**带碰撞多边形（在 `arena_01_tileset.tres` 里）。想改成在 TileMap 面板手工刷 → 删掉该脚本即可无缝替换。
- **y-sort**：`Main` / `Arena01` / `Terrain` / 实体都开 `y_sort_enabled`（决定实体之间的前后遮挡）。但**光靠 y-sort 不能保证实体画在地砖之上**：实体与它所在格的地砖排序键相同，会**被地砖盖住**（实测：Terrain `z_index = 0` 时，站在地面的玩家/敌人被脚下的地砖完全遮住，只看得见血条）。所以 `Terrain` 设为 `z_index = -10`（地形永远是背景），靠 y-sort 只负责实体之间的关系。
   **另一个坑**：地形曾经和"地面贴花"（`MagicField2D`：法阵 / 爆炸，`z_index = -1`）同为 `-1` —— 两者都参与 y-sort，于是爆心下方那些地砖会盖到场地上，**把爆炸圆咬掉一块**（实测：手雷砸下去只看得见半个圆）。分层规则现在是：**地形 -10 ＜ 地面贴花 -1 ＜ 实体 0 ＜ 指示器 100 ＜ 飘字 200**（`verify_grenade` 里有一条断言守着贴花必须高于地形）。改地形 / 新增图层时**必须截图确认**。

## 已知坑（踩过，别重复）

1. **移动/重命名被导入的素材后必须重新导入**。`.import` 文件里 `source_file=` 与 ctex 缓存名（= md5(源路径)）都绑路径。只 `mv` 不重导入 → 加载失败。
   重导入：`godot --headless --path . --import`（或 MCP `manage_import_pipeline` action=reimport）。
   验证是否真的生效：查 `.import` 里 `source_file` 是否已是新路径 —— 别只看 `.godot/imported/` 有没有同名文件，旧缓存会骗你。
2. **`player.tscn` 里 `Body.polygon` 故意是退化值**，由 `player.gd::_fit_body_to_collision_shape()` 在 `_ready()` 里按 `player_shape.tres` 的尺寸推导。原因是编辑器桥无法表达 `PackedVector2Array`。**别删那段代码，也别把退化多边形当 bug 修**。
3. **编辑器桥的 `instantiate_scene` 会把预制的子节点一起写进父场景**（缺 `index=` 覆盖标记）→ 加载时与预制自带子节点**重名重复**（实测：玩家出现 6 个子节点、2 个激活相机）。插入实例后要确认父场景 `.tscn` 只保留 `[node ... instance=ExtResource("…")]` 一行加必要的覆盖属性，然后 `editor_control` action=reload。
   验证方式：探针里 `player.get_children().size()` 应为 **4**（CollisionShape2D / Body / Camera / Skills）。
4. **编辑器 MCP 会话记录只在编辑器启动时写一次**（`.godot/godot_agent_loop/editor-session.json`）。任何 headless 编辑器进程（`--import` / `--export-*`）都会覆盖并删掉它 → 之后 MCP 的 `editor_*` / `run_project` 会被拒绝（`pause state could not be confirmed`）。处理：重启一个编辑器窗口，或 `editor_session ensure`（launchIfNeeded）。
5. **`.gd.uid` 必须跟脚本一起移动**（uid 决定引用解析）；移动脚本后同时更新引用它的 `.tscn` 里的 `path=`。不要手写或手删 uid 文件。
6. `project.godot` 的 `[editor_plugins] enabled` 里出现过重复的裸名条目（`"godot_agent_loop"`，与规范路径条目并存），会让每次 headless 编辑器启动多打一行 `ERROR: Condition "p_enabled && addon_name_to_plugin.has(addon_path)"`。删掉裸名条目可以消掉这行，但**会复现**（插件/编辑器保存项目设置时又写回来）。
7. **Godot 4.7 删掉了 `CollisionObject2D.add_collision_exception_with()` / `get_collision_exceptions()`**（旧文档/旧代码里到处都是）。要让投射物不撞发射者，得用碰撞层 + 自己记 `_caster` 引用（见上方“碰撞层约定”）。判据：`--check-only` 会直接报 `Function "add_collision_exception_with()" not found in base self`。
8. **实体被地砖盖住**：只开 `y_sort_enabled` 不够 —— 实体的排序键和它脚下那格地砖相同，地砖后画就把实体盖掉了（表现：人物/敌人消失，只剩血条浮在上面）。修法是让地形当背景（`Terrain.z_index = -1`，已设）。**任何 y-sort / z_index / 图层改动都要用截图或像素取样确认，别只看节点属性。**
   取样小技巧：headless 下 `root.size` 默认只有 64x64，跑截图断言前先 `root.size = Vector2i(1152, 648)`；读像素用 `root.get_texture().get_image().get_pixelv()`，不要用 `get_screen_transform()` 自己算坐标（相机 `position_smoothing` 时它不可靠）。
9. **新增 `class_name` 脚本后，`--check-only` / 无编辑器跑会报 `Could not find type "Xxx"`** —— 因为 `.godot/global_script_class_cache.cfg` 没更新。跑一次 `--import` 就会刷新（同一个 `--import` 还会生成 `.gd.uid`）。注意该进程会覆盖并删除 `.godot/godot_agent_loop/editor-session.json`（见坑 4）：需要保留正在开的编辑器会话就先把该文件备份再拷回去。

10. **插件的 `AbilityNodeBase._get_target_list()` 会炸**：它写 `var target_list: Array[Node] = context.get(target_key)`，context 里没有那个 key（返回 null）时直接报 `Trying to assign a value of type "Nil" to a variable of type "Array[Node]"` 并中断这次 tick。→ **任何交给插件的施放 context 都要带 `targets`（空数组也行）**（`IndicatorPreview2D.get_result_context()` 和 `AbilityInputRouter.release()` 都加了）。
    同一个函数导致的第二个坑：`AbilityNodeApplyEffect.use_instigator_as_fallback` 插件里**没被用上**（`_tick` 写死 `_get_target_list(instance, false)`）→ 自身效果（dash 这种）必须用一个 `AbilityNodeTargetSearch` + `SelfTargetingStrategy` 先把施法者写进 `targets`，再 apply。
11. **插件是 3D-first 的**：投射物实体、位移效果、指示器预览、命中检测、Cue 全是 `Node3D`/`Vector3`（26 个文件用 3D 类型，1 个用 Vector2）。2D 项目只能白嫖它的**框架层**（技能定义/特性/冷却/行为树/属性/血条/效果/状态/标签/伤害计算），凡是"和世界打交道"的部分都得在 `skills/two_d/` 自己实现（已写好：指示器预览、2D 投射物节点、2D 位移效果、固定伤害策略）。它的 `ui/*.tscn` 也别用：内部路径写死成 `res://addons/gameplay_abiltiy_system/...`（少了 `godot_`、`ability` 还拼错）+ `res://assets/theme/theme_main.tres`，全是坏引用。
12. **插件脚本把 autoload 单例当全局标识符用**（`GameplayAbilitySystem` / `AbilityEventBus` / `TagManager` / `DamageCalculator` / `GameplayCueManager`）。这些名字只在**正常 project 运行**（场景启动、autoload 已注册）时能编译。用 `--check-only --script xx.gd` 或 `--script`（自定义 SceneTree）会报 `Identifier not found: GameplayAbilitySystem` —— **这是假错误**。校验插件相关脚本要跑场景（见"常用命令"），别用 `--check-only`。
13. **导出预设的 `exclude_filter` 曾经是 `addons/*`**，会把运行期要用的技能插件一起排除出 APK（技能全部失效）。现在只排除 `addons/godot_agent_loop/*`、`addons/godot_ability_system/docs/*`、`examples/*`。动这个字段前先想清楚哪些 addon 是运行期依赖。
14. **子模块不要手改**：`addons/godot_ability_system` 是 git 子模块（pin 在某个 commit）。要升级用 `git submodule update --remote addons/godot_ability_system`（然后提交新的 pin）；要改行为就在 `skills/two_d/` 里继承/包装它的类。直接改子模块里的文件会让下次升级冲突。
15. **插件的预览/指示器只有显式 cancel 才会消失 —— 游戏侧必须做“唯一 owner”**。插件从不在自己内部结束预览（`is_finished()` 它根本不调用），而且 `preview_strategy` 上只存**一个** `_indicator` 引用。所以只要多一次 `begin()` 就永久残留一个指示器。实际踩到的两条路径：
    - **一次触摸 = 一次 press 两次**：Godot 默认 `input_devices/pointing/emulate_mouse_from_touch = true`，一个手指会同时产生 `InputEventScreenTouch` 和模拟的 `InputEventMouseButton`。`SkillButton` 原先用 `NO_POINTER(-1)` 既表示“无指针”又表示“鼠标按住”，鼠标分支按下后 `_pointer_id` 仍是 -1 → 两个事件都通过“还没按下”的判断 → `press()` 两次 → 第二次 `begin()` 覆盖 `_indicator`，第一个指示器永远留在地图上（表现：手指抬起后指示器不动了/一直挂在场上）。修法：鼠标用独立哨兵 `MOUSE_POINTER(-2)`，谁是第一个按下的事件谁就拥有按钮，另一个事件忽略（两条事件顺序都测）。
    - **不可预览的技能**：`GameplayAbilityComponent.request_ability_preview()` 在“瞬发 / 智能施法 / 无预览策略”时**先 return null，不走取消旧预览那段**，于是“按 A 瞄准中再按 B（不可预览）”会留下 A 的指示器。修法：`AbilityInputRouter` 成为预览的唯一 owner —— `press()` 先 `_cancel_preview()`，`release()/cancel_aim()/equip()` 都走同一个 `_cancel_preview()`（不带参数，取消该 caster 当前的预览），并在 `_process` 里加看门狗：`_previewing_slot < 0` 但插件仍有预览 → 取消它。
    另外 `IndicatorPreview2D.begin()` 现在会先释放自己拥有的旧指示器（防御重复 begin），指示器带 `name = "SkillIndicator"` 并加入 group `skill_indicators` —— **任何时候没有人在瞄准，这个 group 就必须是空的**，可以直接拿它做断言/排查。相关约束：不要给 `is_finished()` 写 `return _active`（基类返回 true 才是对的语义：结果随时可取，由游戏决定何时 confirm）。

16. **插件的 `disable_ability()` 实际上什么都没做**：`GameplayAbilityInstance.disabled` 是个 “get 返回 `_definition.disabled`” 的属性，所以 `disable_ability()` 写进去的值读出来就没了（`can_activate_ability()` 看的是 `instance.disabled`）。→ “死亡/被控就不能施放”这类规则要**在游戏侧做**：`AbilityInputRouter` / `AiAbilityRouter` 都先问 caster 的 `is_alive()`（实体约定），玩家的 `player.gd` 死亡时只负责变灰/停手/关掉输入。不要靠 `disable_ability` 当护栏。
17. **插件的标签库只认注册过的标签，而且不能指望目录扫描帮你排好继承**：`frozen.tres` 里写的 `tags = [&"status.frozen", &"state.frozen"]` 如果没注册，`TagManager.add_tag/remove_tag` 会 `push_warning` 并静默失败（`has_tag`/过滤器都拿不到）。修法：游戏启动时 `TagManager.initialize("res://skills/data/shared/tags/")`（`main.gd::_ready()` 里做了——**新的入口场景也要做**）。另外 `initialize()` 会在扫描**之前**就把自己标成已初始化，于是每个 `register_tag` 都会立刻重建缓存 —— 子标签可能先于父标签被读到，报 “Parent tag [x] not found”。所以本项目的标签**故意都是平的（`parent_tag_id` 空）**，值需要层级时不要靠目录扫描，改成显式按顺序 `register_tags([...])`。
18. **编辑器桥的几个坑（实测）**：
    - `add_node` 的 `properties` 里混入 layout（anchors/offsets）以外的属性（`text`、`theme_override_*`）会 `property_not_found` → 拆成两次事务：先 `add_node` 只给布局，再 `set_properties` 给文本/字体/颜色。
    - 同一个事务里 `attach_script` 后再 `assign_resource` / `set_properties` 会 `resource_or_property_invalid`（脚本还没生效就被用来校验属性）→ **attach_script 单独一次事务**。
    - 颜色只能传**分量全相等**的 `{r,g,b,a}`；`{r:1,g:0.95,b:0.55,a:1}` 这种会被写成 `Color(0,0,0,1)`（黑）。非灰度颜色直接改 `.tscn` 文本（`theme_override_colors/font_color = Color(1, 0.95, 0.55, 1)`）然后 `editor_control` action=reload。
    - `instantiate_scene` 会把预制的子节点**内联复制**进父场景（父场景里出现 `Title2/Reason2/…` 重复节点）→ 插完实例要确认父场景 `.tscn` 只留 `[node name="X" parent="…" instance=ExtResource("…")]` 一行，然后 reload（即坑 3）。
19. **施放方向的优先级：预览策略 confirm 出来的 `target_direction` 不能被 router 的原始瞄准方向覆盖**。`AbilityInputRouter._activation_context()` 早先无条件写 `context["target_direction"] = _aim_direction`，而**单击（tap）时 `_aim_direction` 恰好是 `Vector2.ZERO`** → 预览策略算出的“默认朝向（自动瞄准最近敌人）”被丢掉 → `AbilityNodeSpawnProjectile2D._resolve_direction()` 退回 `instigator.facing`（= 上一次移动方向）→ **单击 shot 朝反方向飞**。正确优先级：**当前正在拖的方向（非零）> 预览 confirm 的结果 > caster facing**。
    验证侧的教训：断言要问“**飞到哪**”，不能只问“有没有放出去”。旧套件只查了“冷却是否启动”，所以这个方向回归没被发现。现在 `verify_indicator` 里有两条：`a tap flies at the nearest enemy even when facing away`（故意把 `facing` 设成反方向）、`a dragged cast flies along the drag`。

21. **预览策略是“每个定义一份”，绝不能让多个施法者共用 —— 每个 caster 必须拿自己的副本**。插件的 `GameplayAbilityInstance` 直接读写 `_definition.preview_strategy`，而 `.tres` 里的 strategy 是**一个共享实例**，它身上存着 `_caster` / `_indicator` / `_direction` / `_active`（见 `IndicatorPreview2D`）。于是第二个施法者一开镜，就会释放掉第一个施法者的指示器节点（`begin()` 里的防御性 `_release_indicator()`），它 cancel 时取消的也是“最后开始的那个”。单个施法者时看不出来，一旦 ①敌人也会放同一技能 或 ②第二个玩家（多人化）就立刻错乱。
    修法在游戏侧（子模块不动）：`AbilityLoadout2D.private_definition()` 给每个 caster 一份**浅拷贝**的 definition + 一份拷贝的 strategy；行为树 / 特性 / 效果 / 预制场景 / 指示器外观仍然共享（冷却计时本来就存在 ability *instance* 的黑板上，所以共享特性是安全的）。两个 router 都走它，`equip()` 也因此改成按 `ability_id` 比较（`_equipped` 里现在是副本，不是 inventory 里的那个资源）。`IndicatorPreview2D.forget_state()` 负责把副本里的运行时字段清干净：`duplicate()` 会把 `_indicator` 引用一起带过来，不清的话新 caster 的第一次 `begin()` 会释放**别人的**指示器。
    断言：`verify_indicator` 的 “two casters” 段（6 条）——共享版会挂：两个 caster 同时瞄准只剩 1 个指示器、cancel 一个把另一个也带走。
    ⚠️ 同一类“共享资源上有可变状态”的隐患还有一处：`GE_ApplyDamage._apply()` 会写自己的 `damage_multiplier *= context.get("damage_multiplier", 1)`（写在**共享**的 effect 资源上）。默认 1 时无害，但别通过 context 传 `damage_multiplier`，否则会永久污染那个共享效果。

22. **预览策略只在 `update()` 里刷新，所以 `release` 前必须把当前拖动推给它**。`ability_input_router.release()` 会先调 `drag()`（那只更新 router 自己的 `_aim_direction`），然后 `confirm_targeting()`；而策略里的 `_target_position` / `_direction` 只在 `update()`（由 router 每帧的 `_process` 调用）里重算 —— 同一帧内"拖动 + 松开"会确认**上一帧的**瞄准（表现：快速甩一下，手雷落在旧位置或默认落点）。修法：`release()` 里先 `_component.update_targeting(0.0, {"aim_direction": _aim_direction})` 再 confirm。凡是在 `update()` 里缓存状态的 strategy 都有这个坑。
23. **投掷物有两种"到达方式"**：直线的（命中身体即停，`lob = false`）和抛掷的（`ProjectileData2D.lob = true`：飞越身体与墙、按 `max_distance` 落地才炸，`_body` 用正弦包络做假抛物线 + 自旋）。投射物节点用 `target_position_key` 把"落点"换算成方向 + 距离，所以"扔到指定坐标"不需要新脚本。注意 `lob` 的落点不做墙体检测：落点可能在墙里（目前接受，后续要加就把落点夹到可行走格）。

24. **子节点不能在父节点"正在装配子节点"时往父节点加东西**：`MatchDirector._ready()` 里 `get_parent().add_child(unit)` 会报 `Parent node is busy setting up children`（director 的 `_ready` 正是在 Main 装配自己的过程中被调用的）。修法：`_spawn_and_start.call_deferred()`（下一帧再生成），并发出 `units_ready` 让 HUD/相机在那时绑定。同一个坑在测试里也踩过（在 `_ready` 里往 `root` 加场景也会失败）。
25. **`Camera2D` 一旦离开场景树就会自己 `enabled = false`**，所以"把相机 reparent 到另一个单位"这种观战写法会得到一个不会再渲染的相机（`make_current()` 也救不回来，甚至没有报错）。本项目改成**一台常驻相机 + 跟随目标**（`UnitCamera.follow`，`setup()` 换人），换视角就变成一次赋值。
26. **脚本被 host 工具改过之后，编辑器的内存里还是旧版本**：`editor_transaction` 会在 `assign_resource`/`set_properties` 时报 `resource_or_property_invalid` / `property_not_found`（因为新属性在编辑器的旧脚本里不存在），改写过的场景用新类也可能 `node_not_found`。修法：改完脚本重启编辑器会话（`pkill` 掉编辑器 + `editor_session ensure launchIfNeeded=true`），它会重新扫描；**别急着怀疑资源路径**。（另：`add_node` 的 properties 只放布局，`attach_script` 单独一次事务，见坑 18。）
27. **3v3 的出生行有墙**：蓝队出生点在第 5/8/11 行（左侧 cols 2），红队在右侧 col 37，而地图第 5-6 行 cols 6-11 是墙。测试里把两个单位放在出生行对射会被墙挡住（表现是"对手打不到我"），所以 `verify_match` / `verify_3v3` 的射击断言都先把单位挪到**第 11 行那条开阔通道**（y = 368）。

## 常用命令

```bash
GODOT=/Applications/Godot.app/Contents/MacOS/Godot
PROJ=/Users/zhaojie/godot_project/ahh

# 静态校验脚本（无输出 = 通过）
"$GODOT" --headless --path "$PROJ" --check-only --script res://entities/player/player.gd

# 导入 / 重新导入素材（移动资源后必须）
"$GODOT" --headless --path "$PROJ" --import

# 跑主场景 120 帧并看日志（不弹窗，适合 CI/快速自检）
"$GODOT" --headless --path "$PROJ" --quit-after 120

# 生成 / 重新生成全部数据（技能 + 标签 + 敌人技能；改动技能结构后跑一次；必须当场景跑，见坑 12）
# 会覆盖同名 .tres，之后数值改在编辑器里改
"$GODOT" --headless --path "$PROJ" res://skills/data/build/generate_ability_data.tscn

# 全部回归套件（125 条：对局闭环 35 / 指示器 30 / 命中反馈 19 / 手雷 17 / 3v3 团队 24）
# 套件必须当场景跑（见坑 12）。headless 会丢掉 Input.parse_input_event，所以那两
# 条会 SKIP（102/102）；要拿满 104 条用 --windowed。
./tests/run.sh                 # headless：123/123 + 2 SKIP，exit 0
./tests/run.sh --windowed      # 完整 125/125，exit 0
# 单跑某套（调试时用）：
"$GODOT" --headless --path "$PROJ" --fixed-fps 60 res://tests/verify_3v3.tscn       # 24/24

# 截图脚本（windowed）：/tmp/grenade_aim.png（射程环 + 落点圆）、/tmp/grenade_blast.png（爆炸 + 25 飘字）
"$GODOT" --path "$PROJ" --fixed-fps 60 res://tests/shots_grenade.tscn   # 手雷瞄准/爆炸
"$GODOT" --path "$PROJ" --fixed-fps 60 res://tests/shots_result.tscn    # /tmp/result.png：结算 + 计分板

# CI：.github/workflows/tests.yml（每次 push/PR：装 Godot 4.7.2 + `--import` + ./tests/run.sh）

# 子模块
git submodule update --init --recursive
git submodule update --remote addons/godot_ability_system   # 升级插件并提交新 pin

# Android 导出（debug 签名；JAVA_HOME 必需，见坑 4）
export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
"$GODOT" --headless --path "$PROJ" --export-debug "Android" build/ahh.apk
```

用 pi / Godot Agent Loop（MCP）时优先走 MCP：**改场景**用 `editor_transaction`（可撤销），**运行观察**用 `run_project` + `game_*`，**断言**用 `verify_project`。不要手写 `.tscn`。

> 若 MCP 报 `Project path is outside the allowed roots`：MCP 服务进程没拿到路径白名单。它只认启动时的环境变量 `GODOT_MCP_ALLOWED_DIRS`（如 `/Users/zj/godot_project`）；pi 下这个值来自 `@beremaran/godot-agent-loop` 的 `agent-plugin/adapter-manifest.json` 的 `mcp.environment`，**只在 session 启动时读一次** → 改完要重开 session / 重启 pi。

## 验证状态（截至本文件编写时）

- 已验证（3v3 团队层，`tests/verify_3v3.tscn` **24/24**）：花名册 5 个英雄各有签名技能 + 通用 dash；每侧 3 个出生点且**都在可走地板格**（读竞技场 ASCII 图验证）、两侧间隔 > 400px；6 个单位各属一个队伍 group；**同队不敌对、异队敌对**（`Teams.*`）；队友的投射物穿过玩家**不掉血**、对手的投射物掉血；队友的法阵**不 tick 玩家**（即使数据里写的是旧 `target_group = enemies`）；计分板每人一行、伤害/击杀按队伍过滤、本地玩家行带 `human` 标记、按伤害排序
- 已验证（3v3 对局，`tests/verify_match.tscn` **35/35**）：开局 spawn 3v3（1 人 + 5 AI）、READY 冻结、时钟 1:00、比分 3:3；敌人真的打到玩家；**只死本地玩家时对局继续**、相机切到活着的队友；团灭红队 → `YOU WIN` + 结算 + 计分板 6 行；Rematch 重开并复活 6 人；**平分到点 → 加时 30s → 加时里先掉人方输**（reason 写明 Overtime）；frost 冻住 bot → `is_silenced()` 为真
- 已验证（视觉）：大厅（START）→ 选人（5 张英雄卡、选中高亮）→ 3v3 实战（比分 `3 : 3`、法阵 tick 8/5 飘字）→ 结算（`YOU WIN` + HERO/KILLS/DAMAGE 三列，Bomber (you) 3 杀 250 伤害，红队三行 `- down`）；截图脚本 `tests/shots_result.gd` → `/tmp/result.png`
- 已验证（插件链路，场景断言套件 `.godot/verify_abilities.tscn` **32 条全过**）：加载后玩家学到 `shot`/`dash` 两个技能；敌人经插件 vital 初始化到 100/100；点击 shot → 出 2D 指示器且**默认指向最近敌人** → 松手发射 → 子弹带插件伤害效果 → 命中敌人**准确扣 10 血** → 冷却经 `CooldownFeature` 拦住第二次施放 → 冷却结束恢复；dash → 指示器指向敌人**反方向** → 位移正好 168px 且远离敌人；触摸取消不留指示器也不施放；十发把敌人打死并自毁
  （注：该场景已不在仓库里，见常用命令的说明）
- 已验证（对局闭环，`tests/verify_match.tscn` **37 条全过**，windowed/headless 都过）：开局停在 READY 且世界暂停、倒计时播报、时钟 1:00；倒计时结束自动进入 PLAYING 且时钟递减；**敌人主动射击→子弹命中玩家→一次固定扣 10 血（1.00→0.90）**，且不误伤同类；敌人全灭 → `YOU WIN` + 结算面板 + 世界冻结；Rematch 重载场景回到 READY 并恢满血；60s 到 → 按剩余血量比例判胜负（差 ≤ 5% 平局）；玩家阵亡 → `YOU LOSE`，玩家节点保留（相机），死亡后无法起预览/施放；frost 命中敌人 → `is_silenced()` 为真且敌人真的停火；标签库已注册（`TagManager.get_tag_resource(&"state.frozen") != null`）
- 已验证（指示器生命周期，`tests/verify_indicator.tscn`）：windowed **30/30**（含引擎真实触摸路径、瞄准方向、两个施法者互不干扰），headless **28/28 + 2 SKIP**（headless 会丢弃 `Input.parse_input_event`）。两个历史对照：指示器残留 bug 未修时该套件只能过 3/20（一次触摸出 2 个指示器并累积不清）；共享 strategy（坑 21）未修时 “two casters” 段挂 6 条
- 已验证（视觉）：自动瞄准的箭头指示器、飞行中的子弹、敌人血条随插件伤害变短、按钮冷却扇形 —— 截图脚本 `tests/shots_grenade.gd`（往 `/tmp/grenade_*.png` 写图）；本轮的 READY（倒计时 + `GO!`）、PLAYING（时钟 + 指示器）、结算面板（`YOU LOSE` + Rematch）都已用 `game_screenshot` 看过
- 已验证（真人实战）： `run_project` 开的窗口里手工玩了一局：被敌人打死 → 结算 `YOU LOSE` → Rematch → 新一局 READY，控制台 0 error（只有插件的 info 输出）
- 已验证（命中反馈，`tests/verify_feedback.tscn` **19/19**，windowed/headless 都过）：一次命中生成 1 个飘字、数值=实际伤害、位置在血条之上、约 0.75s 自毁；命中瞬间身体变白再回落；被击中 → trauma 上升 → `Camera2D.offset` 偏移 → 约 1s 后精确归零；敌人中弹播 `hit.wav`、玩家中弹播 `player_hit.wav`（更响更低）、施放播 `shoot.wav`、死亡播 `death.wav`、结算播 `win/lose`；只施放不产生飘字。真机外实测：真实窗口里 `game_get_audio` 在施放后立刻看到 2 路 `playing: true`，截图看到玩家头顶红色 `10`
- 已验证（手雷，`tests/verify_grenade.tscn` **18/18**，windowed/headless 都过）：瞄准时同时出现"射程环（跟随施法者）"和"落点圆"；点一下落点圆直接压在最近敌人身上；拖动 25% 射程的像素 → 落点圆落在 25% 射程处；拖过头被夹在射程边缘；松手后**爆炸正好发生在瞄准点**；圆内目标掉正好 25 血（1.00→0.75）且**不伤投掷者**；飞越中间的身体不提前爆炸（敌人血量不变，爆炸在更远处）；2s 冷却内第二次施放被拦；**爆炸圆完整**（地面贴花 z_index 高于地形，见坑 8）；截图 `/tmp/grenade_aim.png`、`/tmp/grenade_blast.png`
- 已验证（回归资产）：4 套断言 **104 条**都在受版本管理的 `tests/`（`./tests/run.sh` → headless 102/102 + 2 SKIP，`--windowed` → 104/104），CI 见 `.github/workflows/tests.yml`（装 Godot 4.7.2 + `--import` + 跑套件）。以前它们在 `.godot/` 里，已被缓存清理丢过一次
- 未验证：真机/模拟器安装与运行、真实触摸（手指）路径、多人同步、多敌人（>1）时的胜负与手感（现在场上敌人固定是 main.tscn 里那一个，重开靠 `MatchDirector.restart()` 重载场景；没有生成器）

> 本文件的技能章节（下方）是硬约束：**新技能 = 组合现有 Action/Effect + 参数 + 条件**，不要为每个技能写专门的脚本。

可以。这个文件的目标不是把代码实现细节全部规定死，而是让 AI 在通过 Godot MCP 修改项目时，始终遵守“组合式、数据驱动技能系统”，避免 AI 后面越写越乱。


## 技能系统

> **实现位置（2026-09 起）**：本节的设计原则（数据驱动 / 组合优于继承 / 表现反应于玩法 / 不写技能专用脚本）**保持不变**，但落地载体已经从自研的 `SkillData + SkillAction` 换成了 **`addons/godot_ability_system` 插件（git 子模块）**：
> - 技能**定义** = 插件的 `GameplayAbilityDefinition`（`.tres`，在 `skills/data/`）：`features`（冷却/消耗/输入…）+ `execution_tree`（行为树）+ `preview_strategy`（瞄准指示器）
> - 技能**行为** = 行为树节点（插件的 `AbilityNode*` + 本项目的 2D 节点）+ `GameplayEffect`（伤害/位移/状态…）
> - 技能**实体** = 还是本项目的 Godot 场景（`entities/*`）
> - 插件缺的 2D 部分（指示器/投射物/位移/命中）= `skills/two_d/` 里的继承扩展
>
> 下文中"`SkillData` / `SkillAction` / `SkillExecutor` / `SkillIndicator`"这些自研类**已经删除**，只作为设计原则参考（对应实现见上面三条）。不要在它们的基础上继续加东西。

1. Project Goal

This project is a 2D real-time multiplayer action game inspired by games such as Brawl Stars.

Core characteristics:

* 2D mobile game
* Short matches
* Multiple playable heroes
* Each hero can have multiple skills
* A large number of skills, effects, buffs, debuffs, projectiles, areas, and interactions
* Skills should be easy to create, modify, combine, and reuse
* The project must remain maintainable as the number of heroes and skills grows

The most important architectural principle is:

Prefer composition over inheritance.

Do not create a separate monolithic implementation for every skill.

⸻

2. Core Architecture

The skill system uses:

Composition
+
Data-Driven Design
+
Godot Nodes / Scenes
+
Reusable Skill Actions

The conceptual architecture is:

SkillData
    ↓
SkillExecutor
    ↓
SkillContext
    ↓
SkillAction[]
    ↓
Game Entities / Effects
    ↓
Godot Nodes

A skill should generally be composed from multiple reusable actions.

For example:

Fireball
├── SpawnProjectile
├── Damage
├── Burn
└── Knockback

Instead of:

FireballSkill.gd
    ├── projectile logic
    ├── damage logic
    ├── burn logic
    └── knockback logic

⸻

3. Composition Over Inheritance

This is the most important rule in the project.

Do NOT create deep skill inheritance hierarchies such as:

Skill
└── ProjectileSkill
    └── FireProjectileSkill
        └── BurningFireProjectileSkill
            └── BurningKnockbackFireProjectileSkill

Prefer:

Skill
├── SpawnProjectile
├── Damage
├── Burn
└── Knockback

Actions should be small, reusable, and composable.

For example:

IceProjectile
├── SpawnProjectile
├── Damage
└── Slow
DashAttack
├── Dash
├── DamageArea
└── Knockback
HealingSkill
├── FindTargets
└── Heal

The goal is to make new skills mostly a matter of composition rather than writing new gameplay logic.

⸻

4. SkillData

Skills should primarily be data-driven.

A skill should have a data representation similar to:

class_name SkillData
extends Resource
@export var skill_name: String
@export var cooldown: float
@export var actions: Array[SkillAction]

The exact implementation may evolve, but the principle must remain:

Skill configuration should be separated from skill execution logic.

A .tres resource should be preferred for static skill configuration.

Example:

skills/
├── colt/
│   ├── basic_attack.tres
│   └── super.tres
├── shelly/
│   ├── basic_attack.tres
│   └── super.tres
└── common/
    ├── dash.tres
    └── projectile.tres

Do not hard-code large amounts of skill configuration inside hero scripts.

⸻

5. SkillAction

A skill is a sequence or composition of reusable actions.

Conceptually:

class_name SkillAction
extends Resource
func execute(context: SkillContext) -> void:
    pass

Possible actions include:

Damage
Heal
Dash
Knockback
Pull
Teleport
ApplyBuff
ApplyDebuff
SpawnProjectile
SpawnArea
SpawnEntity
ModifyStat
FindTargets
PlayAnimation
PlayEffect
PlaySound

New actions should be introduced when a behavior is:

1. Reusable
2. Conceptually independent
3. Useful across multiple skills
4. Easier to reason about as an independent operation

Do not create an Action class for every tiny implementation detail.

Avoid unnecessary abstraction.

⸻

6. SkillContext

Skill execution should have a context object.

Conceptually:

SkillContext
├── caster
├── target
├── targets
├── position
├── direction
├── skill
├── world
└── runtime data

The context allows actions to operate on the current skill execution without tightly coupling every action to a specific hero.

For example:

DamageAction
    ↓
context.targets

instead of:

DamageAction
    ↓
Hard-coded reference to HeroA

Actions should be reusable across heroes.

⸻

7. Godot Nodes vs Skill Logic

Do not turn every gameplay concept into a Godot Node.

Use Godot Nodes for objects that exist in the game world.

Examples:

Hero
Projectile
Area
Trap
Pet
Explosion
FireZone
Pickup

These are appropriate as:

Node2D
CharacterBody2D
Area2D
etc.

Use Resources or normal objects for reusable skill logic and configuration.

Examples:

SkillData
SkillAction
Damage configuration
Buff configuration
Effect configuration

The distinction is:

"How the skill behaves"
        ↓
Resource / logic
"What physically exists in the game world"
        ↓
Godot Node

⸻

8. Projectile Design

A projectile is a game-world entity.

Therefore, it should generally be represented by a Godot Scene/Node.

Example:

projectiles/
└── basic_projectile/
    ├── BasicProjectile.tscn
    └── BasicProjectile.gd

The skill should request the creation/configuration of the projectile.

The skill should NOT contain all projectile movement, collision, lifetime, rendering, and physics logic.

Prefer:

Skill
    ↓
SpawnProjectileAction
    ↓
Projectile.tscn
    ↓
Projectile.gd

The projectile is responsible for being a projectile.

The skill is responsible for deciding that a projectile should be spawned.

⸻

9. Effects

Gameplay effects should also be reusable.

Examples:

Damage
Heal
Burn
Poison
Slow
Stun
Shield
Knockback
Knockup
Silence

Avoid implementing these effects separately inside every skill.

Bad:

Fireball.gd
    apply_burn()
IceBall.gd
    apply_slow()
PoisonBullet.gd
    apply_poison()

Prefer reusable effect implementations:

DamageEffect
BurnEffect
SlowEffect
PoisonEffect

Then skills compose these effects.

⸻

10. Trigger-Based Gameplay

The architecture should support event/trigger driven gameplay.

Examples:

OnHit
OnDamage
OnKill
OnTakeDamage
OnCast
OnDash
OnDeath
OnProjectileHit
OnEnterArea
OnExitArea

A passive ability can therefore be represented conceptually as:

OnKill
    ↓
Heal

or:

OnTakeDamage
    ↓
Condition: HP < 30%
    ↓
ApplyShield

This avoids creating a separate hard-coded implementation for every passive ability.

⸻

11. Conditions

Skill actions may require conditions.

Examples:

Target is enemy
Target is alive
Target is within range
Caster HP < 30%
Target has Burn
Target does not have Shield
Critical hit

Conceptually:

Condition
    ↓
Action

Example:

If HP < 30%
    ↓
ApplyShield

Conditions should also be reusable when appropriate.

Do not duplicate identical condition logic across many skills.

⸻

12. Skill Execution

A skill should generally follow this conceptual flow:

Player Input
    ↓
Hero
    ↓
SkillExecutor
    ↓
SkillData
    ↓
Create SkillContext
    ↓
Execute Actions
    ↓
Modify Game State
    ↓
Spawn / Modify Godot Nodes
    ↓
Visual / Audio Feedback

The Hero should not contain all skill-specific gameplay logic.

The Hero should primarily provide:

Input
State
Position
Stats
Movement
Skill ownership
Skill execution

⸻

13. Example Skills

Basic Projectile

BasicAttack
├── SpawnProjectile
└── Damage

Fireball

Fireball
├── SpawnProjectile
├── Damage
└── Burn

Ice Bullet

IceBullet
├── SpawnProjectile
├── Damage
└── Slow

Dash Attack

DashAttack
├── Dash
├── DamageArea
└── Knockback

Healing Skill

HealingSkill
├── FindAllies
└── Heal

Explosive Projectile

Rocket
├── SpawnProjectile
└── OnProjectileHit
    ├── DamageArea
    └── Knockback

⸻

14. Do Not Over-Engineer

This project does NOT require a full ECS architecture by default.

Do not introduce ECS simply because the project has many skills.

Godot’s Node/Scene architecture should remain the foundation.

Prefer:

Godot Nodes
+
Resources
+
Composition
+
Events
+
Reusable Actions

over introducing a complete ECS framework unless there is a demonstrated technical requirement.

The goal is maintainability and development speed.

⸻

15. File Organization

Prefer colocating a scene and its script when they represent the same game entity.

Example:

entities/
├── hero/
│   ├── Hero.tscn
│   └── Hero.gd
│
├── projectile/
│   ├── Projectile.tscn
│   └── Projectile.gd
│
└── fire_zone/
    ├── FireZone.tscn
    └── FireZone.gd

Skill-related code can be organized as:

skills/
├── core/
│   ├── SkillData.gd
│   ├── SkillAction.gd
│   ├── SkillContext.gd
│   └── SkillExecutor.gd
│
├── actions/
│   ├── DamageAction.gd
│   ├── HealAction.gd
│   ├── DashAction.gd
│   ├── KnockbackAction.gd
│   ├── SpawnProjectileAction.gd
│   └── ApplyBuffAction.gd
│
├── effects/
│   ├── BurnEffect.gd
│   ├── SlowEffect.gd
│   └── PoisonEffect.gd
│
└── data/
    ├── hero_a/
    └── hero_b/

The exact folder structure can evolve, but the architectural separation should remain clear.

⸻

16. When Using Godot MCP

When modifying the project through Godot MCP:

1. Inspect the existing architecture before creating new files.
2. Reuse existing Actions, Effects, Conditions, and Entities whenever possible.
3. Do not create duplicate implementations of existing gameplay behavior.
4. Prefer composition over creating a new specialized skill class.
5. Prefer SkillData/Resources for static skill configuration.
6. Prefer Godot Scenes/Nodes for world entities.
7. Keep Hero scripts independent from individual skill implementations.
8. Do not introduce ECS unless explicitly requested or technically justified.
9. Do not create unnecessary abstractions.
10. Preserve the existing architecture when adding new features.

Before implementing a new skill, ask:

Can this skill be implemented by composing existing Actions?

If yes, compose existing Actions.

If not, ask:

Is the missing behavior reusable enough to become a new Action/Effect?

If yes, create a reusable Action/Effect.

Only create a skill-specific implementation when the behavior is genuinely unique and cannot reasonably be expressed through the existing composition system.

⸻

17. Avoid Skill-Specific God Objects

Do not create classes such as:

AllSkills.gd
SkillManager.gd
HeroSkillManager.gd
GameSkillManager.gd

that contain hundreds or thousands of lines of skill-specific logic.

Managers should coordinate systems.

They should not become repositories for every game’s special case.

Bad:

if skill_id == "fireball":
    ...
elif skill_id == "ice_ball":
    ...
elif skill_id == "dash":
    ...
elif skill_id == "rocket":
    ...

Prefer:

SkillData
    ↓
SkillAction[]
    ↓
SkillExecutor

⸻

18. Reusability Rule

Before writing new gameplay code, search for an existing implementation.

For example, if a new skill needs:

Damage

do not create:

FireballDamage.gd
IceDamage.gd
RocketDamage.gd

Reuse:

DamageAction

If a new skill needs:

Knockback

reuse:

KnockbackAction

The objective is to build a small number of highly reusable primitives that can express many skills.

⸻

19. Skill System Design Philosophy

The system should make this possible:

Small number of primitives
            +
        Composition
            =
Large number of skills

For example:

10 Actions
×
Different parameters
×
Different combinations
=
Many different skills

Do not optimize for the smallest amount of code.

Optimize for:

* Reusability
* Composability
* Testability
* Predictability
* Easy balancing
* Easy iteration
* Easy addition of new heroes
* Easy addition of new skills

⸻

20. Multiplayer Consideration

The game is intended to support real-time multiplayer.

Therefore, skill logic should be designed so that gameplay state can eventually be authoritative on the server.

Avoid putting critical gameplay state exclusively inside visual Nodes or animation callbacks.

Separate:

Gameplay State

from:

Presentation

For example:

Damage

should be gameplay logic.

While:

Play hit animation
Play sound
Spawn hit particle

are presentation.

The architecture should make it possible to execute/validate gameplay actions independently from purely visual effects.

⸻

21. Presentation Separation

Gameplay:

Damage
Heal
Move
Dash
Knockback
ApplyBuff
SpawnProjectile

Presentation:

Animation
Particle
Sound
Camera Shake
Screen Effect

Do not make gameplay correctness depend on whether an animation or particle node exists.

For example:

Damage
    ↓
Game State changes
Hit VFX
    ↓
Presentation reacts to the damage

not:

HitAnimation
    ↓
Actually apply damage

⸻

22. AI Implementation Rule

When an AI agent is asked to implement a new hero or skill, it should first identify:

1. What is the skill's gameplay behavior?
2. Which existing Actions can express it?
3. Which existing Effects can express it?
4. Which existing Conditions are required?
5. Does the skill need a new world Entity/Node?
6. Does a genuinely new reusable Action/Effect need to be created?

Only after answering these questions should code be written.

The AI should prefer:

Reuse existing primitive

over:

Create a new specialized implementation

⸻

23. Final Architectural Principle

The most important rule of this project is:

A new skill should usually be created by composing existing capabilities, not by creating a new class containing all of its behavior.

Think:

Skill = Composition of Actions + Parameters + Conditions + Effects

not:

Skill = One Large Script

Godot Nodes represent things that exist in the world.

Resources represent reusable configuration and skill definitions.

Actions represent reusable behavior.

Effects represent reusable gameplay consequences.

Events/Triggers connect gameplay situations to actions.

Presentation reacts to gameplay instead of defining gameplay.

Keep the system simple until real complexity requires additional abstraction.