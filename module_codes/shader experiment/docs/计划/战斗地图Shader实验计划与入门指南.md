# 战斗地图Shader实验入门与路线

> 更新：2026-11-14。当前主线是“参考视角预绘侧面＋相对映射”，本文件只保留与当前原型一致的入门说明。

## 1. 当前做什么

- 角色：原生像素待机，固定Z=0，普通AnimatedSprite2D。
- 地面：矩形世界平面，经片元射线求交显示透视。
- 建筑正面：wall1矩形素材，局部面UV采样。
- 建筑侧面：wall2带透视和Alpha，局部面UV先映射到参考四边形再取色。
- 相机：固定朝+Z，A/D改X、W/S改Height，不支持旋转。

按F5进入Reference，按钮切换到普通Nearest场景并可返回。最新参数和节点见说明目录，不从本文件复制旧配置。

## 2. Shader、材质、脚本各做什么

| 部分 | 职责 |
| --- | --- |
| Shader（.gdshader） | 程序，决定绘制片元的颜色与Alpha |
| ShaderMaterial | Shader加上这栋建筑独有的图片、颜色、矩阵和几何数据 |
| Node脚本 | 相机输入、世界参数、包围框、向材质传值 |
| SpriteFrames | idle.png切帧与播放，不是建筑Shader的一部分 |

同一个Shader可以供多份材质使用；三栋楼必须有各自材质，因为box_min / box_size不同。两个旧Shader与Reference Shader都是独立文件，没有gdshaderinc或全局参数登记。

## 3. 一帧如何画出来

1. map_camera.gd更新相机。
2. fighter_preview.gd把脚点投到屏幕，设置显示位置与比例。
3. building.gd更新世界盒子、z_index、角点投影包围框。
4. reference_building.gd计算预绘侧面四角映射。
5. battle_map.gd调用相机方法把同一相机状态传给各材质。
6. GPU在ColorRect覆盖的像素上执行fragment()，射线命中表面后采样素材。

CPU正向投影负责“在哪个屏幕矩形里画”，GPU反向映射负责“该矩形内每个像素画什么”。这两部分不是可以随意删掉的重复代码。

## 4. Inspector应该改什么

- 相机：MapCamera的Height / Horizon / Focal Length / Ground Position。
- 玩家：Ground Position、Jump Height、World Units Per Texel；Transform是计算结果。
- 建筑：Ground Position、World Size；Reference建筑另有Side Reference Corners。
- 地面材质：Ground Texture、Ground Min / Max、Tile Size、Guide Z。
- Reference建筑材质：Front Texture / Side Texture、Tint、Side Brightness。

CameraRuntime、box_min/box_size、side_reference_map是脚本输出；不要手改后期待它不被覆盖。

当前无@tool：停止运行时不实时投影。修改Local并保存后运行；即时实验修改Remote节点，Remote修改不等于下次启动配置。

## 5. 代码阅读重点

```glsl
vec3 ray = vec3((FRAGCOORD.x - screen_size.x * 0.5) / focal_length,
    (horizon - FRAGCOORD.y) / focal_length, 1.0);
```

这是当前视口像素对应的未归一化观察方向。地面求Y=0交点，正面求固定Z交点，侧面求固定X交点。

Reference侧图采样：

```glsl
vec3 reference = side_reference_map * vec3(face_uv, 1.0);
vec2 reference_uv = reference.xy / reference.z;
```

side_reference_map是局部单位面→预绘素材四边形，不是再次把整张预绘图压成梯形。四角解释见方案B制作说明。

## 6. 制作与显示的正确边界

- Aseprite逐像素绘制；素材有效像素、世界体量、参考屏幕尺寸分别记录。
- 角色与远景可使用不同世界像素密度；不要求相同源图必须代表相同世界高度。
- 不要求每个源色块在任何深度都变成相同屏幕方块；允许倾斜和近似协调。
- 当前1280×720是渲染试验规格，不再依据角色源像素反推分辨率；源图与世界体量仍各自配置。
- 当前使用Nearest与参考映射，不作“任意机位绝不闪烁”的保证；提高内部渲染采样是本轮单独验证项。

## 7. 下一步与暂不实施

下一步按研究计划H02开始：在1280×720内部画布以同一路径慢移，区分纹理跳色、Alpha轮廓跳步和裁边；随后校准一栋楼的wall2四角和体量。

太阳/月亮、原生灯光与阴影、屏幕光束、轮廓亮边、Bloom是不同效果。本轮不加它们；待几何与素材稳定后分别建立实验，避免用强光/模糊掩盖采样问题。也不继续推行没有证据的固定8层或精灵堆叠。

相关：`横版像素格斗地图伪3D像素稳定性研究计划.md`、`../说明/参考视角侧面方案B制作与使用说明.md`。Godot官方CanvasItem Shader：`https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/canvas_item_shader.html`。

## 8. 正式地图素材

绘制完整地图母稿、记录地平线/主点、放双角色参考、按面与深度拆层、补齐遮挡内容和标定辅助侧面，请按 [Aseprite分层绘制与交付规范](../方案/格斗地图Aseprite分层绘制与交付规范.md)。当前不具备自动把Aseprite图层导入世界空间的功能；先完成一栋建筑的制作-接入-极限机位闭环，再量产地图。
