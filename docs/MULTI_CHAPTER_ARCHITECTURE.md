# 多章节架构与第二章独立机制

状态：已实施  
范围：两章、每章 10 关、稳定 ID 与独立关卡数据

## 1. 当前结构

章节由 `MigrationLevelCatalog.chapter_definitions()` 提供：

```text
ChapterDefinition
├── id / number
├── title / subtitle
├── accent_color / landscape_tint
├── node_positions
└── levels[]
    ├── id / chapter_id / level_index / global_index
    ├── optimal_days / recommended_days
    ├── intended_paths / branch_paths
    ├── partner_cells / checkpoint_cells
    └── watchtower_cells / watchtower_reveal_radius
```

界面和存档只使用稳定的 `chapter_id` 与 `level.id` 识别内容，数组下标仅用于当前页面
导航。第一章最后一关完成后，第二章与 `c2_l01` 自动解锁。

## 2. 第二章内容原则

- 数字目标仍为 24，棋盘保持 8×12。
- 10 张地图均独立手工编排，不复制或镜像第一章。
- 瞭望点是本章专属可选机制：额外绕路换取大范围驱雾。
- 后半章组合伙伴、水塘、瞭望点与多个旧道路前沿。
- 每关保留精确 BFS 最优值，普通推荐线为最优值加 1。
- 作者路线和明确支路属于设计解空间，完全不接触它们的路径才计为数字噪音。

## 3. 当前存档

当前进度格式为 v4，旧 v1/v2/v3 存档会自动补齐新增字段：

```text
[completed] / [best_days] / [partners] / [watchtowers]
[home]
chapter_1_decoration="natural"
chapter_2_decoration="wind_chimes"
```

声音、震动、减少动态与语言使用独立的 `link24_settings.cfg` 保存。

## 4. 验证

- 20 关作者路线、全部明确支路、伙伴、水塘与瞭望点通过模型测试。
- 测试会拒绝第二章路线等于第一章原布局或水平镜像。
- 求解器验证精确最优日、推荐线、选择密度和意外路径阈值。
- 锁定章节预览不会写入正式进度。

开发时直接进入第二章第 11 关：

```sh
/Applications/Godot_mono.app/Contents/MacOS/Godot \
  --path . -- --chapter=2 --play
```
