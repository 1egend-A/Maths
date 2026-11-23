> 状态：2026-11-23 · 可直接粘贴的简历条目（中文为主，末尾附英文速写）

# 简历条目

用法：每个岗位挑 3–5 条，宁少勿多；同一项目在不同岗位下换侧重（研究岗突出验证方法，工程岗突出实现与交付）。

## 数学建模竞赛（2026 国赛 C 题）

- 作为建模主力完成微电网购电优化四问：单日 LP、日前计划（5 倍紧急购电惩罚）、滚动两阶段调整、实时波动电价下的 CVaR 差异化，四问全部交付。
- 问题二最优方案总费用 **1,456.5 万元**，并量化出储能价值 **184 万元**与预测误差代价 **232 万元**，把「储能值不值」从定性判断变成可核算数字。
- 用「日末闭环」等式对结果做指纹校验，发现首版模型中的冗余变量并剔除，避免交付一个更"完整"但多余的模型。

## 仿真建模（2026 新能源汽车能量流）

- 从零搭建能量流与热管理基准模型，场景 A 能耗 **14.61 kWh/100km**，五项守恒校验残差达 **0 J** 量级，步长收敛验证误差 0.041%。
- 定位并修复两个致命实现错误：制动/回收工况符号写反（能耗曾虚高 70 倍）、中心差分加速度与速度离散不匹配（产生虚假惯性功）。
- 论文由构建脚本生成而非手改，支撑材料 494 件经必要性审计后定稿，并完成论文与压缩包的逐项一致性审计。

## MathorCup 赛道 A（啤酒风味预测）

- 为 227 维化学成分到感官属性的预测建立 **333 条数字护照**（值 + 出处 + 引用位置），保证论文 198 行数字引用全部可追溯。
- 设计三口径收敛性检验（全样本中位 / bootstrap 中位 / 零重合占比），证伪「网络路径可作为独立第三条证据」的原假设。
- 用实测数据删掉一条题设的预处理规则（同源组内 ARI 仅 0.0016，低于随机基线），避免语义同族被误当统计冗余。

## AI 应用（学术论文审稿智能体）

- 设计「三角色并行审稿 + 主编仲裁 + QC 门禁」的七阶段流水线，规则版 3 ms 出结果、模型版 8–10 秒出 9 条意见。
- 用 978 篇论文做有效性评测，发现主指标无分辨力（0.1911 vs 打乱配对零模型 0.1935），主动停用并改为报告零模型对照。
- 建立 52 篇 / 27 刊校准语料，实测暴露评分尺子的体裁偏差（中位 59、30/52 被假 desk-reject 封顶、T1/T2 无区分），据此补出第六个评分维度。

## 量化研究（A 股选股工作流）

- 迭代 7 版策略（v3.0→v3.6），用 **11,883 样本**滚动验证推翻自己的 v3.1 假设——两个核心因子的方向与直觉相反。
- 建立分窗口验证方法论：跨窗口一致率 **≥80% 才可用**、≈50% 判为噪声，替代容易过拟合的池化显著性检验。
- 设计三本账分离的账本与复盘制度，首次完整到期复盘证明：组合亏损 10% 的期次里，止损规则挽回 **4.62 个百分点**。

## 工程实现（BOLL 通道筛选）

- 实现纯规则 BOLL 通道选股系统，18 项单测（含无前视检查），全市场 **4,792** 只标的 8 分钟筛出 9 只。

## 期货策略

- 将双均线长周期参数由 10 调至 20，年化收益 26.31%、夏普 1.188、最大回撤降至 19.51%，交易次数减少 38%（增收又降险的帕累托改进）。

---

## 英文速写（投外企 / 英文简历时改写）

- Built an end-to-end paper-review agent (3 reviewer roles + editor arbitration, 7-stage pipeline); rule-based path returns in 3 ms, model path in 8–10 s.
- Ran a 978-paper validity evaluation and retired the primary metric after finding it no better than a shuffled-pairing null (0.1911 vs 0.1935).
- Calibrated the scoring rubric against 52 papers from 27 journals, exposing a genre bias (median 59; 30/52 capped by a false desk-reject rule).
- Optimized a microgrid day-ahead purchase plan (LP + rolling two-stage + CVaR), total cost ¥14.57M with storage value and forecast-error cost quantified separately.
- Iterated 7 strategy versions with 11,883-sample rolling validation, overturning two of my own hypotheses when they failed out-of-window.

> 英文条目只是素材，正式使用时按岗位改写，别直译。
