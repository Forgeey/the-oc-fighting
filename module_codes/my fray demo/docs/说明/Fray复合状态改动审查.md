# Fray 复合状态改动审查

> 2026-11-11 后续实施：已重新核对上游 #54／#55，当前 _goto/_can_switch 已有等价旧缺陷修复。本轮真正增加组完成递归等待，并同步根和 Demo 两份 compound_state.gd；删除游戏层重复完成条件。以下旧“插件未改／空 end_state 为 true／父条件绕过”均是此前审查快照，不再代表当前语义。最新补丁和测试见[复合状态完成与条件作用域处理](复合状态完成与条件作用域处理.md)。

> **2026-11-10 当前采用范围：**done 不是必须状态，路线允许在 B/C/D 多处完整恢复收招，按父出口条件判断；子组条件全部本地注册，暂不考虑继承根条件。本文的 done 实验与否定回退修复建议仅保留为历史审查，不是当前实施前置或待办授权。最新设计见[组合技路线条目与多出口设计方案](../方案/组合技路线条目与多出口设计方案.md)。

> 两项边界的具体接线（done／局部完成查询、owner 条件绑定／保留否定前缀的最小修复建议）见[复合状态完成与条件作用域处理](复合状态完成与条件作用域处理.md)。当前根直接使用原生 FrayCompoundState，本次未修改插件。

> 审查日期：2026-11-10。结论：**不建议整包回退；先保留已验证生命周期修复，把语义扩展和真实修复分别管理。**本次只改文档，在临时副本做对比，不修改、同步覆盖或回退正式 Fray 源码。

## 1. 审查基线：不能把版本升级当成自定义大改

- `6662fed`（2025-07-20）是较早引入 Fray 的仓库版本。
- `1ada138`（2026-10-17）已经是当前 2.0.0-alpha 接口布局：state_mgmt、SequenceMatcher、HitState 等。相比更早目录有大量新增／移动／删除，不代表这些全是后续自定义生命周期补丁。
- `dee825b`（2026-10-24）记录了相对此接口基线的主要本地状态管理改动；已有 `addons/fray/Fray_复合状态生命周期修复对比.md` 记录 2026-10-22 的设计说明。
- 本审查用 `git diff 1ada138 HEAD -- addons/fray/src` 区分已提交的本地改动，再单独看工作区未提交的两项修复。
- **这里的 1ada138 是仓库可确认的历史接口基线，不宣称它是网上官方最新版或完全未经修改的上游。**未拉取／重置远程仓库，不能用一个旧 hash 代替“回到最新官方版”。

## 2. 实际差异与建议

| 位置 | 改动性质 | 是否应因采用组流程而回退 |
| --- | --- | --- |
| `input/autoloads/fray_input.gd` | 已提交的 `ispressed`→`is_pressed` 拼写修复 | 不应回退，和组结构无关 |
| `hit/2d/hit_state_2d.gd` | 工作区 get_hitboxes 的内部 Array 改为 Array[FrayHitbox2D]，匹配返回声明 | 保留；业务已经正常使用 typed 返回值 |
| `input/sequence/sequence_tree.gd` | 工作区取／删分支的索引边界条件修复 | 保留，合法索引和越界已有测试 |
| `compound_state.gd` 叶子进入／退出与默认入口 | 初始化／进入组时统一展开并进入真实叶子，避免漏 enter | 应保留或用同等正确的最小补丁替代；组 start=B／grab 恰好依赖它 |
| `compound_state.gd` 的 ready 根引用刷新 | 子树先构造、后挂根时传播最终 root 引用 | 按需保留并回归；新局部组不应拿到已失效根引用 |
| `_get_transition_priority` | 修正 get_transition 返回对象后的错误属性读取 | 保留真实类型修复；普通边优先级仍需按实际扫描策略处理 |
| 普通规则 self-edge 跳过 AStar 自边 | 自身转换从生命周期处理，不把自边送给寻路图 | 有自重入测试时保留；不应因减少分组而回退 |
| 选中具体边再 external 转换 | 自边可真正退出／重入，保留明确源而非一律 goto | 是语义＋机制修正，需保留测试；不能无证据声称全部上游约定如此 |
| 子规则优先于父规则 | 改变父／子同时匹配时的胜出顺序 | **行为选择，不全称 bug 修复。**本项目组合技局部后续优先、父级全局出口回退的设计可使用；若要强制受击／死亡优先，单独规定调度，不靠旧的任意父边抢占 |
| goto 默认／历史展开、无效目标预解析、goto 当前叶子不重入 | 导航行为扩展与生命周期一致性 | 可以在后续精简，但须先列调用依赖；不能与普通规则 external 自转移混为一谈 |
| state_machine.initialize 第三个 initial_path | 兼容保留两参数的新可选参数；直接进入指定叶子／组 | 当前 Fighter 还传第三参数，直接回退签名会报参数数目错误；如要缩回两参先迁移调用并验证首叶子进入 |
| `_is_transitioning` 与旧信号断开 | 禁止 enter／exit 中同步递归切换、重新初始化连接管理 | 属于生命周期约束；不是给 Builder 增加“护城河”。若不保留需明确替代重入策略，不能在组 enter 再 goto(start) |

## 3. 两份插件副本核对

比较根 `addons/fray` 与 demo 的实际加载副本，对下列文件检查内容（归一 CRLF／LF）：

- state_mgmt/state/compound_state.gd：一致。
- state_mgmt/state_machine.gd：一致；原始哈希可能因换行不同。
- input/autoloads/fray_input.gd：一致；原始哈希可能因换行不同。
- hit/2d/hit_state_2d.gd：一致。
- input/sequence/sequence_tree.gd：一致。

这只说明关键文件行为相同，不意味着全仓所有 demo 副本已经同步。本轮没有做全仓批量复制。

## 4. 实验：原生组入口用法也会触发旧版缺陷

临时工程使用两组副本：

- current：当前 demo 插件源码。
- baseline：只把 CompoundState、StateMachine 两个脚本换成仓库 `1ada138` 版本，其他文件不动。

测试树：根 idle 与 combo 同级；combo.start_state=B，子状态 B／C，根和组用公开 initialize、goto、add_transition、advance 操作。叶子仅记录 enter／exit，不用项目 Fighter／攻击框业务。

| 操作 | 当前版本观测 | 历史两脚本版本观测 |
| --- | --- | --- |
| initialize 默认 idle | idle.enter 一次 | 当前地址虽为 idle，但没有 idle.enter |
| goto(combo)，默认 B | idle.exit、combo.enter、B.enter | idle.exit、combo.enter，**漏 B.enter** |
| B→C 输入边与父组即时出口均成立 | 走子边到 C | 父边先执行，退出到 idle |
| 已在 C 时 goto(combo/C) | 无重复 enter | 此行初始路径不同，仅作显式寻址观测，不据此推断全部场景等价 |
| 组返回 idle | 叶子、组退出，再 idle.enter | 本次退出链可运行，但不能弥补之前漏进入 |

漏进入不是“错误理解 CompoundState 才造成”：进入组、让 start_state 选择 B 就会出现。因此正确使用组合技／投掷组后，更不能无条件恢复这个历史行为；否则 B 的计时、动画、抓取目标初始化可能根本没运行。

## 5. 组合技／投掷最小用例的额外发现

当前插件的 19 项临时用例包括：A→combo 取消条件、默认 B 进入一次、B→C、done 完成、非 persistent 重入、throw→grab、captured 成功分支和失败恢复，均通过（失败分支采用组内条件绑定，见下）。这只是原生机制验证，不是完整 MK 组合技、抓取判定或双方同步已经落地。

### 5.1 end_state 只检查当前子状态身份

`_is_done_processing_impl()` 返回 end_state 为空或 current_state==end_state，不自动等最后攻击叶子完成。已在用例验证：把 end_state 直接设成 C，刚进入 C 就可能组完成。

建议用显式非攻击 done，末段完成后 AT_END 到 done；或者在特定组定义完成语义。**这是当前 Fray 的既有机制，不把它当成“旧大补丁已修掉的问题”。**

### 5.2 子组回退到根条件时会丢否定（现存，未修复）

当前和 `1ada138` 都有同样逻辑：先 trim `!`，本地查不到时调用 root.is_condition_true(condition)，传给根的已是去掉否定的名字。

例如根 captured=false：

```text
root.is_condition_true("!captured")  → true
throw.is_condition_true("!captured") → false（本地未绑定时）
```

这会让“抓取超时且 !captured”边错误失败；反过来根 captured=true 时又可能让失败边具备不应有的条件。因此新子组接入前必须测试。回退历史两脚本也不能解决，因为这个问题原来就存在。

本轮不改插件。可先在 throw 子组明确绑定 captured／capture_failed 本地事实，避免走有问题的否定继承；正式实现若依赖全局取反，单独做保存 `!` 语义的最小修复，并同步两份副本及测试，不为此整包替换状态机。

## 6. 回退决策

**现在不做 git reset、checkout 或覆盖整个 addons/fray。**用户要求本轮“查查是不是应该改回”，不是已经确认回退方案。

推荐顺序：

1. 保留三项独立输入／类型／索引缺陷修复。
2. 保留叶子正确进入／退出、子树 root 引用等已证实需要的行为，先接正确的局部组。
3. 父／子规则顺序、persistent、goto 自身语义、initial_path 等作为单独扩展列清单；确无调用需求再删除／缩小补丁，不能整包回旧版。
4. 子组结束和条件 scope 先写最小测试；继承否定另提单行级修复，不把它藏进文档整理任务。
5. 若要回到某个上游版本，先固定上游来源／版本，迁移当前 initialize 调用与测试，再在隔离分支运行全套回归，最后确认同步根和 demo 副本；不是只看场景能否启动。

具体目标设计见[角色动作与复合状态组织方案](../方案/角色动作与复合状态组织方案.md)。当前正式 runtime／插件文件本轮均未改变；审查实验、错误观测都只发生在临时项目。
