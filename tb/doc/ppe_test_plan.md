# PPE 顶层测试点分解

语言：中文 | [English](ppe_test_plan.en.md)

## 简要说明

本文档仅分解PPE顶层测试点，不包含验证平台、参考模型、完整覆盖率方案或回归策略。
测试只使用顶层输入输出，DUT内部实现视为黑盒。输入/输出lane数为可变参数，范围为3～7；
测试点描述不依赖某个固定lane数。

### 默认检查

以下性质由验证环境在所有测试中持续检查，不再为其单独设置测试点：

- `out_monitor`按输出起始lane采集报文，并检查同周期`out_valid`连续、无空洞以及跨最高lane循环。
- `scb`按顶层实际接收顺序建立期望队列，逐包检查数据、依赖结果和输出顺序，并在测试结束时检查输出总数及待输出队列。因此，丢包、重复输出、意外输出和乱序属于所有测试的默认检查。

后续表格中的检查机制仅强调该测试点需要额外关注的采集或比较内容；上述默认检查始终有效。

下列表格中的“随机”均指在协议合法范围内受约束随机；每个C段明确列出随机变量及需要固定或定向处理的变量。

## 1. 性能维度

| ID | 测试点 | 测试点描述 | 检查机制 | FCOV | 用例映射 |
| --- | --- | --- | --- | --- | --- |
| PERF-001 | 峰值吞吐 | C: `valid`固定满宽，`packet`随机，delay=0，dep_offset=0，无复位。I: 持续发送长流。PO: 统计顶层接收吞吐、输出吞吐、反压比例和延迟。 | `in_monitor`统计接收；`out_monitor`统计输出及延迟。 | 满宽负载、delay=0、dep=0命中。 | `tc_performance`（未实现） |
| PERF-002 | Delay混合吞吐 | C: `valid`随机非空，`packet`随机，delay在0～3内随机，dep_offset=0，无复位。I: 持续发送长流。PO: 统计稳态吞吐和延迟。 | `in_monitor`统计输入及delay分布；`out_monitor`统计输出及延迟。 | delay 0～3均命中。 | `tc_performance`（未实现） |
| PERF-003 | Dependency混合吞吐 | C: `valid`、`packet`和delay随机，dep_offset按指定依赖比例随机且目标合法，无复位。I: 分别发送无依赖、低、中和高依赖比例的长流。PO: 统计稳态吞吐和反压比例。 | `in_monitor`统计依赖比例和接收；`out_monitor`统计输出。 | 无依赖、低、中、高依赖比例分别命中。 | `tc_performance`（未实现） |
| PERF-004 | 负载强度 | C: `packet`随机，delay=0，dep_offset=0，无复位；`valid`数量按目标负载定向约束。I: 分别发送稀疏、中等和满宽输入。PO: 比较接收率、输出率和延迟。 | `in_monitor`统计输入宽度和接收；`out_monitor`统计输出及延迟。 | 稀疏、中等、满宽负载分别命中。 | `tc_performance`（未实现） |
| PERF-005 | 稳态对比 | C: 各输入变量沿用被比较负载的约束，RTL版本间配置、seed和随机序列一致，无复位。I: 发送足够长的相同测试流。PO: 排除启动和排空影响后比较不同RTL版本。 | `in_monitor`和`out_monitor`按相同窗口统计。 | 启动、稳态和排空区间均有统计样本。 | `tc_performance`（未实现） |

## 2. 接口维度

`in_monitor`负责采集实际接收事务，`out_monitor`负责采集输出事务，`scb`负责端到端检查。

| ID | 测试点 | 测试点描述 | 检查机制 | FCOV | 用例映射 |
| --- | --- | --- | --- | --- | --- |
| IF-001 | Valid模式 | C: `valid`定向遍历全部模式，`packet`和delay随机，dep_offset随机且目标合法，输入遵守`bkps`。I: 逐一发送全部valid模式。PO: 仅有效lane形成实际接收事务。 | `in_monitor`记录实际接收mask；默认检查验证对应输出。 | valid mask全部取值。 | `tc_if_basic`（未实现） |
| IF-002 | Data边界 | C: `valid`和delay随机，dep_offset随机且目标合法；`packet`定向取全0和全1，其余取值随机。I: 发送数据边界值及随机数据。PO: 输出与packet及descriptor对应的结果一致，无数据错配。 | `in_monitor`采集输入packet；`out_monitor`采集输出packet；`scb`检查预期数据。 | data最小值、最大值。 | `tc_if_basic`（未实现） |
| IF-003 | Delay | C: `valid`和`packet`随机，delay在0～3内随机，dep_offset随机且目标合法。I: 持续发送随机delay报文。PO: 每个报文使用自身delay并产生正确结果。 | `in_monitor`采集delay；`scb`比较对应处理结果。 | delay 0、1、2、3分别命中。 | `tc_if_basic`（未实现） |
| IF-004 | Dependency | C: `valid`、`packet`和delay随机，dep_offset在0～7内随机且非零目标合法。I: 持续发送随机依赖报文。PO: 无依赖报文使用零依赖数据，有依赖报文使用准确的第K个前序报文结果。 | `in_monitor`建立接收顺序并采集dep_offset；`scb`检查依赖目标和结果。 | dep_offset 0～7；cross `delay × dep_offset`。 | `tc_if_dependency`（未实现） |
| IF-005 | 依赖拓扑 | C: `packet`和delay随机，`valid`及dep_offset按目标拓扑定向生成，所有依赖目标合法。I: 遍历同一生产者被后续7个位置重复依赖的127种非空组合，覆盖消费者同批/跨批分布，并构造依赖链及扇出后继续成链。PO: 所有消费者取得正确目标结果，链上每一级使用直接前驱结果。 | `in_monitor`记录生产者和消费者关系；`scb`检查重复依赖及依赖链结果。 | 消费者数量1～7；依赖链深度；dep_offset 1～7。 | `tc_if_dependency`（未实现） |
| IF-006 | 依赖边界 | C: `packet`随机，`valid`、delay和dep_offset按目标边界定向生成，所有依赖目标合法。I: 定向构造同批稀疏依赖、跨批offset 1/7、生产者delay=3且消费者紧随、目标已输出后再被依赖、同一生产者的消费者分布在目标输出前后，以及依赖跨序号回绕。PO: 每种边界下消费者均取得准确目标结果。 | `in_monitor`记录抽象接收顺序；`scb`检查边界目标和结果。 | 同批、跨批、目标未输出、目标已输出、跨输出边界、回绕分别命中。 | `tc_if_dependency`（未实现） |

重复依赖的127种组合按消费者数量分布如下：

| 消费者数量 | 组合数 |
| ---: | ---: |
| 1 | 7 |
| 2 | 21 |
| 3 | 35 |
| 4 | 35 |
| 5 | 21 |
| 6 | 7 |
| 7 | 1 |

## 3. 功能维度

功能维度与接口维度共用用例规划，不单独建立功能用例；以下测试点合并映射到接口依赖用例。

| ID | 测试点 | 测试点描述 | 检查机制 | FCOV | 用例映射 |
| --- | --- | --- | --- | --- | --- |
| FUNC-001 | Dependency结果 | C: `valid`、`packet`和delay随机，dep_offset定向指向未输出或已输出目标且依赖合法。I: 分别构造两类目标状态。PO: 消费者取得相同且准确的目标处理结果。 | `in_monitor`记录目标关系；`scb`检查依赖结果。 | 目标未输出、目标已输出分别命中。 | `tc_if_dependency`（未实现） |
| FUNC-002 | 多消费者与依赖链 | C: `packet`和delay随机，`valid`及dep_offset按共享目标和依赖链定向生成，所有依赖合法。I: 构造共享目标和多级依赖链。PO: 共享读取及每一级计算均正确。 | `in_monitor`记录依赖拓扑；`scb`逐级检查结果。 | 单消费者、多消费者、依赖链分别命中。 | `tc_if_dependency`（未实现） |
| FUNC-003 | 长流回绕 | C: `valid`、`packet`和delay随机，dep_offset随机且合法，并定向加入跨回绕依赖，无复位。I: 发送足够长的合法流量跨越有限实现编码回绕。PO: 回绕前后的依赖目标及处理结果连续正确。 | `in_monitor`维护抽象接收顺序；`scb`检查回绕边界依赖结果。 | 顺序回绕及依赖跨回绕分别命中。 | `tc_if_dependency`（未实现） |

## 4. 反压维度

| ID | 测试点 | 测试点描述 | 检查机制 | FCOV | 用例映射 |
| --- | --- | --- | --- | --- | --- |
| BP-001 | 全局反压 | C: `valid`固定满宽，`packet`和delay随机，dep_offset随机且合法；目标周期`bkps=1`。I: 在反压期间提供并保持完整输入批次。PO: 所有lane均不接收，不允许部分接收。 | `in_monitor`确认无接收事务；`scb`确认expected数量不增加。 | `bkps`有效期间有输入请求。 | `tc_backpressure`（未实现） |
| BP-002 | 输入保持 | C: `valid`、`packet`和delay随机，dep_offset随机且合法；`bkps=1`后全部输入字段固定保持。I: 分别保持一个周期和多个周期，直至反压解除。PO: 解除后的首个合法接收沿只接收一次。 | `in_monitor`检查输入稳定及单次接收。 | 反压持续1周期和多周期分别命中。 | `tc_backpressure`（未实现） |
| BP-003 | 反压边界 | C: `packet`和delay随机，dep_offset随机且合法；`valid`定向取稀疏和满宽模式。I: 在`bkps`拉高和拉低附近持续发送输入。PO: 每个时钟沿的实际接收集合与`bkps`状态一致，不发生批次部分接收。 | `in_monitor`检查反压边界的实际接收mask；默认检查验证后续输出。 | 拉高、拉低、稀疏批次、满宽批次分别命中。 | `tc_backpressure`（未实现） |

## 5. 复位维度

| ID | 测试点 | 测试点描述 | 检查机制 | FCOV | 用例映射 |
| --- | --- | --- | --- | --- | --- |
| RST-001 | 复位值 | C: `rst_n=0`；`valid`定向取全0和非0，其他输入随机且复位期间不要求形成合法事务。I: 在复位期间施加两类valid。PO: `bkps`有效、全部`out_valid`无效，不接收或输出报文。 | `reset_monitor`检查复位端口状态；`in_monitor`和`out_monitor`确认无事务。 | 复位期间输入无效和有效分别命中。 | `tc_reset`（未实现） |
| RST-002 | 异步断言同步释放 | C: 输入valid=0，其他输入随机；复位断言和释放相位定向到非时钟沿。I: 在时钟运行期间拉低并释放`rst_n`。PO: 断言立即生效，释放仅在同步完成后生效。 | `reset_monitor`检查断言及释放时序；`out_monitor`检查valid状态。 | 异步断言和同步释放分别命中。 | `tc_reset`（未实现） |
| RST-003 | 在途复位 | C: `valid`、`packet`和delay随机，dep_offset随机且合法；复位时机定向到输入等待、报文在途及输出活动阶段。I: 在各目标阶段断言复位。PO: 旧事务全部取消，复位后不得出现旧输出。 | `reset_monitor`记录复位时机；`scb`清除旧expected；`out_monitor`检查无旧输出。 | 输入等待、报文在途、输出活动阶段分别命中。 | `tc_reset`（未实现） |
| RST-004 | 复位后重启 | C: 复位释放后`valid`、`packet`和delay随机，dep_offset在复位后已有历史范围内随机，并定向包含首个合法依赖。I: 发送新的合法流量。PO: 报文顺序、依赖历史和输出起始lane从初始状态重新建立。 | `in_monitor`建立新接收流；`out_monitor`采集输出；`scb`检查复位后结果。 | 复位后首包、首个依赖和首次lane回绕分别命中。 | `tc_reset`（未实现） |

## 6. 场景维度

| ID | 测试点 | 测试点描述 | 检查机制 | FCOV | 用例映射 |
| --- | --- | --- | --- | --- | --- |
| SCN-001 | 反压与复位 | C: `valid`、`packet`和delay随机，dep_offset随机且合法；复位定向发生在`bkps=1`期间。I: 持续发送流量并在反压期间插入复位。PO: 接收边界正确、旧事务取消、复位后正常恢复。 | `reset_monitor`记录复位；`in_monitor`检查接收边界；`scb`检查取消和恢复。 | 反压期间复位及释放后首批次命中。 | `tc_reset`（未实现） |
| SCN-002 | 连续空拍 | C: `packet`和delay随机，dep_offset随机且合法；非空区间`valid`随机非空，空拍区间valid=0，空拍发生在`bkps=0`。I: 连续若干周期发送非空输入，随后连续若干空拍，再恢复非空输入。PO: 空拍周期不形成输入事务，空拍前已接收报文可继续输出，恢复输入后处理连续正确。 | `in_monitor`记录非空批次及空拍区间；默认检查验证空拍前后报文。 | 连续空拍长度及空拍前后非空批次分别命中。 | `tc_if_basic`（未实现） |
| SCN-003 | 单空拍 | C: `packet`和delay随机，dep_offset随机且合法；空拍前后`valid`随机非空，中间一个周期valid=0，空拍发生在`bkps=0`。I: 连续若干周期发送非空输入，插入单空拍并在下一周期恢复非空输入。PO: 单空拍不形成输入事务，空拍前后实际接收序列连续正确。 | `in_monitor`确认两个非空区间之间仅有一个空拍；默认检查验证空拍前后报文。 | 单空拍及其前后非空valid模式命中。 | `tc_if_basic`（未实现） |
