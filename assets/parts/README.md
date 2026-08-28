# 奇妙夜 Demo 素材分段总览

本目录按 `data/story_flow.gd` 的执行顺序拆分为 18 个节点。每个节点目录都包含 `backgrounds/`、`portraits/`、`cg/`、`sfx/` 四个素材子目录及 `.gitkeep`，用于后续替换正式资源。当前项目主要使用 `systems/placeholder_assets.gd` 生成的占位背景、人物和 CG。

| 序号 | 目录 | 关卡名 | scene_id | 类型 | 场景 / 对话 |
|---:|---|---|---|---|---|
| 00 | [00_title](00_title/) | 标题画面 | `title_screen` | title | — |
| 01 | [01_chapter1_prologue](01_chapter1_prologue/) | 第一章：新婚彩排 | `chapter1_prologue` | dialogue | `data/dialogue/chapter1_prologue.json` |
| 02 | [02_chapter2_prologue](02_chapter2_prologue/) | 第二章：结婚前夜 | `chapter2_prologue` | dialogue | `data/dialogue/chapter2_prologue.json` |
| 03 | [03_wonderful_night_intro](03_wonderful_night_intro/) | 奇妙夜：世界 | `wonderful_night_intro` | dialogue | `data/dialogue/wonderful_night_intro.json` |
| 04 | [04_part1_forest_dark](04_part1_forest_dark/) | 黑暗森林 | `part1_forest_dark` | level | `levels/maps/forest_dark.tscn` |
| 05 | [05_part1_dialogue_end](05_part1_dialogue_end/) | PART 1 结束 | `part1_dialogue_end` | dialogue | `data/dialogue/part1_end.json` |
| 06 | [06_part2_forest_path](06_part2_forest_path/) | 森林岔路 | `part2_forest_path` | level | `levels/maps/forest_path.tscn` |
| 07 | [07_part2_parkour](07_part2_parkour/) | 追逐阿麦 | `part2_parkour` | level | `levels/minigames/parkour.tscn` |
| 08 | [08_part2_waterfall_cg](08_part2_waterfall_cg/) | 瀑布 | `part2_waterfall_cg` | cg | — |
| 09 | [09_part2_descent](09_part2_descent/) | 瀑布下降 | `part2_descent` | level | `levels/minigames/waterfall_descent.tscn` |
| 10 | [10_part2_heart_qte](10_part2_heart_qte/) | 心动互动 | `part2_heart_qte` | level | `levels/maps/stream_area.tscn` |
| 11 | [11_part2_stream_dialogue](11_part2_stream_dialogue/) | 溪流 | `part2_stream_dialogue` | dialogue | `data/dialogue/part2_stream.json` |
| 12 | [12_part2_continue_placeholder](12_part2_continue_placeholder/) | PART 2 后半 | `part2_continue_placeholder` | dialogue | `data/dialogue/part2_continue.json` |
| 13 | [13_part3_lake](13_part3_lake/) | 神秘湖 | `part3_lake` | level | `levels/maps/lake_area.tscn` |
| 14 | [14_part3_stone_jump](14_part3_stone_jump/) | 跳石头 | `part3_stone_jump` | level | `levels/minigames/stone_jump.tscn` |
| 15 | [15_part3_lake_dialogue](15_part3_lake_dialogue/) | PART 3 湖畔 | `part3_lake_dialogue` | dialogue | `data/dialogue/part3_lake_end.json` |
| 16 | [16_part4_mystery_girl](16_part4_mystery_girl/) | 神秘女孩 | `part4_mystery_girl` | cg | `data/dialogue/part4_mystery_girl.json` |
| 17 | [17_demo_end](17_demo_end/) | Demo 结束 | `demo_end` | dialogue | `data/dialogue/demo_end.json` |

正式素材可直接放入对应节点的子目录；如需接入运行时，请同步更新素材 catalog 中的路径。
