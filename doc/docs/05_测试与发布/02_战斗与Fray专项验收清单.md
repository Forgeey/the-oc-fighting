# 战斗与 Fray 专项验收清单

## 输入

- [ ] 玩家设备对应正确的 `FrayController`/虚拟设备；
- [ ] 组合/序列输入、方向转换和缓冲窗口符合设计；
- [ ] 输入只被合法 transition 消费一次；
- [ ] 暂停、回合重置和断连后无残留输入。

## 状态机

- [ ] 状态类继承 `FrayState` 且职责薄；
- [ ] 状态拓扑在 builder 中定义；
- [ ] 输入转移由 `FrayBufferedInputAdvancer`/Fray transition 推动；
- [ ] hitstun、blockstun、KO 外部跳转集中管理；
- [ ] 不存在 enum/string 平行状态机。

## 命中

- [ ] strike 使用 `FrayHitbox2D`；
- [ ] strike attribute 直接引用 `FrayAttackAttribute`；
- [ ] damage、硬直、击退、浮空没有第二套参数；
- [ ] 多段、互击、格挡、无敌、角落和 KO 均验证；
- [ ] 中断和回合重置会关闭所有 hitbox。

## 动画

- [ ] `FrayAnimationObserver`/tracker 事件完整；
- [ ] hitbox 启停和动画阶段一致；
- [ ] hitstop、逐帧、慢速和动画中断不会丢失/重复事件；
- [ ] 动画结束正确推动 state done/transition。
