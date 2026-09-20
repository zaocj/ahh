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
| `assets/audio/` `assets/fonts/` | 音频 / 字体原始素材 | 空（占位） |
| `core/battle/` | 战斗编排（回合调度、胜负判定、计分） | 空（占位） |
| `core/network/` | 联网（同步、房间、消息） | 空（占位） |
| `core/events/` | 全局事件总线 / 信号中枢 | 空（占位） |
| `core/utils/` | 跨功能工具函数。现有 `targets.gd`（`Targets.nearest()` / `offset_to_nearest()`：按 group 找最近目标，技能自动瞄准与敌人追击共用） | 有内容 |
| `entities/base/` | 可复用实体基类 | 空（占位，血量改用插件的 vital） |
| `entities/player/` | **玩家**：`player.gd` + `player.tscn` + `player_shape.tres`（`facing` / `dash()` / `is_dashing()`，group `players`） | 有内容 |
| `entities/projectile/` | **投射物**：`projectile.gd` + `projectile.tscn` + `projectile_shape.tres`（匀速直飞，撞墙/打到实体/飞满 `max_distance` 自毁） | 有内容 |
| `entities/enemy/` | **敌人**：`enemy.gd` + `enemy.tscn` + `enemy_shape.tres`（追 `target_group` 里最近的目标，到 `stop_distance` 停下；自带 `Health` 与血条） | 有内容 |
| `entities/hitbox/` | 命中判定盒 | 空（占位） |
| `entities/pickup/` | 拾取物（能量块、补给） | 空（占位） |
| `heroes/base/` | 英雄基类（hero.gd / hero.tscn / hero_data.tres） | 空（占位） |
| `heroes/<hero>/` | **一个英雄一个自包含目录**：`<hero>.gd` `<hero>.tscn` `<hero>_data.tres` 图标/立绘、以及该英雄专属 `skills/` | 空（占位：`warrior/` `ranger/` `assassin/`） |
| `skills/two_d/` | **插件的 2D 适配层**（插件本体在 3D 侧，2D 项目必须自己补）：`indicator_preview_2d.gd`（2D 瞄准指示器 + 默认朝向）、`ability_node_spawn_projectile_2d.gd`（行为树节点：发射 2D 投射物）、`projectile_data_2d.gd`、`ge_dash_2d.gd`（2D 位移效果）、`flat_damage_logic.gd`（固定伤害策略）、`ability_input_router.gd`（按钮 → 插件生命周期）、`ability_loadout_2d.gd` / `stat_block_2d.gd`（把数组型配置塞进 `.tres`）、`skill_indicator.gd` + `skill_indicator_data.gd`（2D 指示器绘制） | 有内容 |
| `skills/data/shared/` | 跨技能共用数据：属性（`max_health`…）、`vitals/health.tres`、`enemy_stats.tres`（属性集 + vital）、`effects/bullet_damage.tres`（GE_ApplyDamage + 固定 10） | 有内容 |
| `skills/data/player/<skill>/` | **一个技能一个目录**：`<skill>.tres`（GameplayAbilityDefinition：特性 + 行为树 + 预览策略）、`preview.tres`、`indicator.tres`、以及该技能的子弹数据 | 有内容（`shot/`、`dash/`、`loadout.tres`） |
| `skills/data/build/` | `generate_ability_data.gd/.tscn`：一键生成上面这些 `.tres`（嵌套资源手写易错）。**只在加/改技能结构时跑一次**，之后在编辑器里改 `.tres` | 有内容 |
| `maps/arena_01/` | **一张地图一个目录**：`arena_01.tscn`（根 `Arena01` + 子 `Terrain` TileMapLayer）、`arena_01_tileset.tres`、`terrain.gd`（按 ASCII 地图刷格） | 有内容 |
| `ui/hud/` | 局内 HUD。现有 `virtual_joystick.gd`（触摸/鼠标摇杆）、`skill_button.gd`（技能按钮：短按直接施放，长按/拖动瞄准） | 有内容 |
| `ui/battle/` | 对局内其它界面（倒计时、结算） | 空（占位） |
| `ui/lobby/` | 大厅 / 主菜单 | 空（占位） |
| `ui/hero_select/` | 选英雄界面 | 空（占位） |
| `main/` | **装配根**：`main.tscn` + `main.gd`（实例化玩家与地图、接线摇杆、HUD 状态） | 有内容 |
| 根目录 | `project.godot`（输入映射 / 主场景 / 渲染设置）、`export_presets.cfg`（Android 预设）、`icon.svg`、`.vscode/` | — |

### 空目录 = 约定占位

空目录表示**领域边界已定、内容还没写**。新功能请放进对应目录，不要另造平级目录（例如别新建 `weapons/`，武器是 `entities/projectile/` 或 `skills/` 的事）。
注意：git 不跟踪空目录 —— 目录里有第一个真实文件后才会被提交。

## 现有内容怎么协作

```
main/main.tscn        Main (Node2D, y_sort_enabled)
                      ├── HUD (CanvasLayer) → Status (Label) + Joystick (Control, virtual_joystick.gd)
                      │                    → SkillBullet / SkillDash (Control, skill_button.gd)
                      ├── Player   ← 实例：entities/player/player.tscn（position 覆盖为出生点 656,368，group: players）
                      │   ├── Abilities  (GameplayAbilityComponent，插件)
                      │   └── InputRouter (AbilityInputRouter：按钮 → 插件施放流程)
                      ├── Arena01  ← 实例：maps/arena_01/arena_01.tscn → Terrain (TileMapLayer)
                      └── Enemy    ← 实例：entities/enemy/enemy.tscn（position 830,260）
```

- **输入**：`project.godot` 里 4 个命名 action（`move_left/right/up/down`，WASD + 方向键）。`player.gd` 用 `Input.get_vector()` 读它们，摇杆则通过 `player.joystick_input` 汇入同一入口。→ 加新操作请加命名 action，不要用 `ui_*`。
- **玩家视觉**：`Player/Body` 是 `Polygon2D`，颜色即"有色方块"。换成正式 Sprite 时删掉 `player.gd` 里推导多边形的代码即可。
- **技能**：由插件驱动，一条链路是
  `HUD 按钮 → AbilityInputRouter.press/drag/release → GameplayAbilityComponent.request_ability_preview() / update_targeting() / confirm_targeting() / try_activate_ability()`。
  **按下**就进预览（指示器立刻出现，响应快），**拖动**超过 `aim_dead_zone` 才覆盖默认朝向，**松手**用 `confirm_targeting()` 的结果施放；所以"点一下"永远走技能的默认方向。冷却、消耗、执行全部在插件里（`CooldownFeature` / `CommitCooldown` 节点 / 行为树）；按钮的扇形遮罩读 `CooldownFeature.get_cooldown_progress()`（`main.gd::_process` 每帧同步）。
- **默认朝向（自动瞄准）**在 `IndicatorPreview2D.default_aim` 上：`FACING` / `TO_TARGET`（朝 `target_group` 里最近目标）/ `AWAY_FROM_TARGET`（反向，后撤 dash）。当前 `shot` = `TO_TARGET`、`dash` = `AWAY_FROM_TARGET`，`target_group` 都是 `enemies`（敌人预制已加入该 group）。没有目标时回退 `facing`。
- **施放结果怎么传到行为树**：预览策略的 `get_result_context()` 返回 `target_direction`（Vector2）/ `target_position`，插件把它作为 context 交给行为树；`AbilityNodeSpawnProjectile2D` 读 `target_direction`，`GE_Dash2D` 也读它。**context 里必须始终带一个 `targets` 数组**（哪怕为空）——见坑 10。
- **加一个新技能**：先在 `skills/data/build/generate_ability_data.gd` 里照着现有段落拼出来（特性 + 行为树 + 预览策略），跑一次 `generate_ability_data.tscn` 生成 `.tres`，把它加进 `skills/data/player/loadout.tres`，再在 `main.tscn` 的 HUD 里加一个 `SkillButton`（顺序 = 槽位顺序）。之后数值都在编辑器里改 `.tres`。**不要给技能写专门的脚本**：优先用插件的特性 + 行为树节点 + 效果组合。
- **伤害路径**：投射物不改血量，它带一串插件 `GameplayEffect`（`payload_effects`，来自 `ProjectileData2D`），命中时 `effect.apply(target, instigator, context)` → `GE_ApplyDamage` → `DamageCalculator`（这里配的是 `FlatDamageLogic` 固定 10）→ 目标的 `GameplayVitalAttributeComponent` → `HealthVital.apply_damage()`。所以**可被打 = 有 `GameplayVitalAttributeComponent` 节点**（投射物用这个名字判断，墙/地形直接被跳过）。伤害数值只写在 `skills/data/shared/effects/*.tres` 与 `flat_damage_10.tres` 里。
- **实体约定**：`facing`（朝向）、`dash(direction, distance, duration)`（可位移，由 `GE_Dash2D` 调用）、group `players`（可被追）/ `enemies`（可被瞄准）、`get_gameplay_ability_component()`（插件查组件的接口，见 player.gd）。血量/属性不写在实体脚本里，挂在插件组件上。
- **地形**：`maps/arena_01/terrain.gd` 的 `ARENA` 常量（每格一字符：`#` 墙、`.` 地面、`o` 地台）在 `_ready()` 里 `set_cell` 刷出来。只有**墙格**带碰撞多边形（在 `arena_01_tileset.tres` 里）。想改成在 TileMap 面板手工刷 → 删掉该脚本即可无缝替换。
- **y-sort**：`Main` / `Arena01` / `Terrain` / 实体都开 `y_sort_enabled`（决定实体之间的前后遮挡）。但**光靠 y-sort 不能保证实体画在地砖之上**：实体与它所在格的地砖排序键相同，会**被地砖盖住**（实测：Terrain `z_index = 0` 时，站在地面的玩家/敌人被脚下的地砖完全遮住，只看得见血条）。所以 `Terrain` 设为 `z_index = -1`（地形永远是背景），靠 y-sort 只负责实体之间的关系。改地形/新增图层时**必须截图确认**。

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

# 生成 / 重新生成技能数据（改动技能结构后跑一次；必须当场景跑，见坑 12）
"$GODOT" --headless --path "$PROJ" res://skills/data/build/generate_ability_data.tscn

# 技能系统断言套件（32 条；同样必须当场景跑）
"$GODOT" --headless --path "$PROJ" --fixed-fps 60 res://.godot/verify_abilities.tscn

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

- 已验证（插件链路，场景断言套件 `.godot/verify_abilities.tscn` **32 条全过**）：加载后玩家学到 `shot`/`dash` 两个技能；敌人经插件 vital 初始化到 100/100；点击 shot → 出 2D 指示器且**默认指向最近敌人** → 松手发射 → 子弹带插件伤害效果 → 命中敌人**准确扣 10 血** → 冷却经 `CooldownFeature` 拦住第二次施放 → 冷却结束恢复；dash → 指示器指向敌人**反方向** → 位移正好 168px 且远离敌人；触摸取消不留指示器也不施放；十发把敌人打死并自毁
- 已验证（视觉）：自动瞄准的箭头指示器、飞行中的子弹、敌人血条随插件伤害变短、按钮冷却扇形 —— 截图脚本 `.godot/shots_abilities.gd`（往 `/tmp/ab_*.png` 写图）
- 已验证（静态/运行）：`git submodule` 就位（pin `a360f40`）；主场景 headless 跑 400 帧 0 error（只有退出时的资源残留警告，插件 teardown 自带的）；插件的 5 个 autoload 在 `project.godot` 里注册
- 未验证：真机/模拟器安装与运行、真实触摸（手指）路径、多人同步、玩家自身的血量/受击（目前只有敌人在插件 vital 里）

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