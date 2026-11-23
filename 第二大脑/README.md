> 状态：2026-11-23 · 个人档案与跨项目经验库（第二大脑入口）

# 第二大脑

一个纯 Markdown 的个人档案库：身份、工作习惯、做过的项目、关键决策与踩过的坑。
目的不是记事，而是让任何一台电脑上的任何 AI 先读这里，就能接着上次的上下文继续工作，而不是从零问一遍。

## 给 AI 的使用规则

1. 先读本文件，再按下面的索引取需要的文件——不要一次读全库。
2. 以文件里记录的事实为准；标注「已证伪 / 仅历史参考」的条目不得当结论使用。
3. 涉及日期、数字、结论时，先看该文件开头的「状态」行判断时效。
4. 一次会话结束，把新增结论追加到对应文件或 `log/`，不要改写旧记录。

## 目录结构

```
第二大脑/
├─ README.md              本文件：入口、规则、索引
├─ me/
│  ├─ profile.md          身份、背景、技术栈、长短板
│  ├─ preferences.md      工作习惯与协作规矩（事实卡片）
│  └─ context.md          当前进行中 / 待办状态
├─ projects/              每个项目一份档案
│  ├─ reviewer-zero.md
│  ├─ astock.md
│  ├─ boll.md
│  ├─ cumcm-2026-c.md
│  ├─ sf-2026-c.md
│  ├─ mathorcup-2026-a.md
│  ├─ gvmarker.md
│  └─ coursework.md
├─ decisions/
│  └─ lessons.md          关键决策与教训（背景 / 决定 / 依据 / 代价）
├─ resume/
│  ├─ achievements.md     量化成果总表（简历第一素材）
│  ├─ bullets.md          可直接粘贴的简历条目（中英）
│  ├─ skills-and-gaps.md  技能矩阵：证据与缺口
│  ├─ targets.md          目标岗位与匹配度
│  └─ honors.md           竞赛奖项与证书（含待补占位）
├─ toolchain/
│  ├─ environment.md      本机环境与工具踩坑速查
│  ├─ md-to-pdf.md        Markdown → A4 PDF 自建链路
│  └─ ai-collaboration.md 与 AI 长期协作：记忆、留痕、远程、成本
├─ plans/
│  └─ monetization.md     内容与技能变现的长期计划
└─ log/
   └─ timeline.md         2026-07 至 2026-11 重大节点
```

## 维护规则

- **绝对铁律：每完成一项有价值的工作（项目、竞赛、策略迭代、方法突破、重大决策），必须提取经验精华回填本库**，主动做、不等提醒。
- **只追加，不重写历史**。要纠错，就在原条目下加一行「更正：……」，保留原判断。
- **写前先 pull**，写完立刻 commit。没 commit 等于没存。
- **待定项标【待定】**。默认值不得冒充已定结论——默认值的危险不在它存在，而在它冒充结论。
- 单个文件超过约 200 行就拆，宁可多几个小文件。

## 内容边界（本仓库公开）

- 不含真实姓名、学校、学号、联系方式、账号。
- 不含线上部署地址中的凭据、token、邀请码。
- 不含具体持仓名单、股票代码与金额。
- 收益类数字只作方法论记录，不构成任何投资建议。

## 索引

| 想了解 | 读 |
|---|---|
| 我是谁、会什么、短板在哪 | `me/profile.md` |
| 我要求怎么干活（做作业、写报告、跑脚本） | `me/preferences.md` |
| 现在手上有哪些没做完的事 | `me/context.md` |
| 某个项目的前因后果 | `projects/<项目>.md` |
| 以前在哪儿摔过跤、为什么 | `decisions/lessons.md` |
| 要写简历、准备面试 | `resume/`（先看 `achievements.md`） |
| 本机环境怎么配、某个报错怎么解 | `toolchain/environment.md` |
| 要自己拼 PDF、公式渲染、压页数 | `toolchain/md-to-pdf.md` |
| AI 怎么记我的事、会话怎么开 | `toolchain/ai-collaboration.md` |
| 长期在盘算什么生意 | `plans/monetization.md` |
| 某个月发生了什么 | `log/timeline.md` |
