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
| `addons/godot_agent_loop/` | 编辑器插件（MCP 桥，`@tool extends EditorPlugin`）。**只在编辑器里跑，不进游戏包**（导出预设已 `exclude_filter="addons/*"`） | 有内容 |
| `assets/textures/` | 共享原始素材。现有 `terrain_atlas.png` = 程序化生成的 4 格图集（地面 / 地面变体 / 墙 / 地台） | 有内容 |
| `assets/audio/` `assets/fonts/` | 音频 / 字体原始素材 | 空（占位） |
| `core/battle/` | 战斗编排（回合调度、胜负判定、计分） | 空（占位） |
| `core/network/` | 联网（同步、房间、消息） | 空（占位） |
| `core/events/` | 全局事件总线 / 信号中枢 | 空（占位） |
| `core/utils/` | 跨功能工具函数 | 空（占位） |
| `entities/base/` | 实体基类（entity.gd / entity.tscn） | 空（占位） |
| `entities/player/` | **玩家**：`player.gd` + `player.tscn` + `player_shape.tres` | 有内容 |
| `entities/projectile/` | 子弹 / 投射物 | 空（占位） |
| `entities/hitbox/` | 命中判定盒 | 空（占位） |
| `entities/pickup/` | 拾取物（能量块、补给） | 空（占位） |
| `heroes/base/` | 英雄基类（hero.gd / hero.tscn / hero_data.tres） | 空（占位） |
| `heroes/<hero>/` | **一个英雄一个自包含目录**：`<hero>.gd` `<hero>.tscn` `<hero>_data.tres` 图标/立绘、以及该英雄专属 `skills/` | 空（占位：`warrior/` `ranger/` `assassin/`） |
| `skills/base/` | 技能基类（skill.gd / skill.tscn） | 空（占位） |
| `skills/<kind>/` | **一个技能一个目录**，按形态分类：`attack/`（普攻）`projectile/`（弹道）`dash/`（位移）`aoe/`（范围）`buff/`（增益） | 空（占位） |
| `maps/arena_01/` | **一张地图一个目录**：`arena_01.tscn`（根 `Arena01` + 子 `Terrain` TileMapLayer）、`arena_01_tileset.tres`、`terrain.gd`（按 ASCII 地图刷格） | 有内容 |
| `ui/hud/` | 局内 HUD。现有 `virtual_joystick.gd`（触摸/鼠标摇杆） | 有内容 |
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
                      ├── Player   ← 实例：entities/player/player.tscn（position 覆盖为出生点 656,368）
                      └── Arena01  ← 实例：maps/arena_01/arena_01.tscn → Terrain (TileMapLayer)
```

- **输入**：`project.godot` 里 4 个命名 action（`move_left/right/up/down`，WASD + 方向键）。`player.gd` 用 `Input.get_vector()` 读它们，摇杆则通过 `player.joystick_input` 汇入同一入口。→ 加新操作请加命名 action，不要用 `ui_*`。
- **玩家视觉**：`Player/Body` 是 `Polygon2D`，颜色即"有色方块"。换成正式 Sprite 时删掉 `player.gd` 里推导多边形的代码即可。
- **地形**：`maps/arena_01/terrain.gd` 的 `ARENA` 常量（每格一字符：`#` 墙、`.` 地面、`o` 地台）在 `_ready()` 里 `set_cell` 刷出来。只有**墙格**带碰撞多边形（在 `arena_01_tileset.tres` 里）。想改成在 TileMap 面板手工刷 → 删掉该脚本即可无缝替换。
- **y-sort**：`Main` / `Arena01` / `Terrain` 都开 `y_sort_enabled`，且 `Terrain.y_sort_origin = 0`。这个值决定玩家能否画在地砖之上，**改完必须截图确认**（踩过：设成 32 时地台格把玩家盖住了）。

## 已知坑（踩过，别重复）

1. **移动/重命名被导入的素材后必须重新导入**。`.import` 文件里 `source_file=` 与 ctex 缓存名（= md5(源路径)）都绑路径。只 `mv` 不重导入 → 加载失败。
   重导入：`godot --headless --path . --import`（或 MCP `manage_import_pipeline` action=reimport）。
   验证是否真的生效：查 `.import` 里 `source_file` 是否已是新路径 —— 别只看 `.godot/imported/` 有没有同名文件，旧缓存会骗你。
2. **`player.tscn` 里 `Body.polygon` 故意是退化值**，由 `player.gd::_fit_body_to_collision_shape()` 在 `_ready()` 里按 `player_shape.tres` 的尺寸推导。原因是编辑器桥无法表达 `PackedVector2Array`。**别删那段代码，也别把退化多边形当 bug 修**。
3. **编辑器桥的 `instantiate_scene` 会把预制的子节点一起写进父场景**（缺 `index=` 覆盖标记）→ 加载时与预制自带子节点**重名重复**（实测：玩家出现 6 个子节点、2 个激活相机）。插入实例后要确认父场景 `.tscn` 只保留 `[node ... instance=ExtResource("…")]` 一行加必要的覆盖属性，然后 `editor_control` action=reload。
   验证方式：探针里 `player.get_children().size()` 应为 **3**。
4. **编辑器 MCP 会话记录只在编辑器启动时写一次**（`.godot/godot_agent_loop/editor-session.json`）。任何 headless 编辑器进程（`--import` / `--export-*`）都会覆盖并删掉它 → 之后 MCP 的 `editor_*` / `run_project` 会被拒绝（`pause state could not be confirmed`）。处理：重启一个编辑器窗口，或 `editor_session ensure`（launchIfNeeded）。
5. **`.gd.uid` 必须跟脚本一起移动**（uid 决定引用解析）；移动脚本后同时更新引用它的 `.tscn` 里的 `path=`。不要手写或手删 uid 文件。
6. `project.godot` 的 `[editor_plugins] enabled` 里出现过重复的裸名条目（`"godot_agent_loop"`，与规范路径条目并存），会让每次 headless 编辑器启动多打一行 `ERROR: Condition "p_enabled && addon_name_to_plugin.has(addon_path)"`。删掉裸名条目可以消掉这行，但**会复现**（插件/编辑器保存项目设置时又写回来）。

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

# Android 导出（debug 签名；JAVA_HOME 必需，见坑 4）
export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
"$GODOT" --headless --path "$PROJ" --export-debug "Android" build/ahh.apk
```

用 pi / Godot Agent Loop（MCP）时优先走 MCP：**改场景**用 `editor_transaction`（可撤销），**运行观察**用 `run_project` + `game_*`，**断言**用 `verify_project`。不要手写 `.tscn`。

## 验证状态（截至本文件编写时）

- 已验证：场景/资源引用完整性；四方向移动、撞墙阻挡、摇杆拖动（抽取前的结构）；Android 可导出并签名
- 未验证：场景抽取（实例化）后的 **y-sort 视觉层次**（需要一次干净截图）、真机/模拟器安装与运行、真实触摸（手指）路径
