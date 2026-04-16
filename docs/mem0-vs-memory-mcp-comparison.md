# Memory MCP vs Mem0 vs AgentCore Memory：三方对比调研

> 调研日期: 2026-04-16

## 1. 概览

| 维度 | Memory MCP Server (当前方案) | Mem0 OSS (Local Mode) | AWS Bedrock AgentCore Memory |
|------|---------------------------|----------------------|------------------------------|
| GitHub Stars | ~2k | ~47k | N/A (AWS 托管服务) |
| 定位 | 最轻量的本地知识图谱 | 通用 AI 记忆层，向量+图谱 | 企业级全托管记忆服务 |
| 存储格式 | 单个 JSON 文件 | Qdrant + Neo4j (可选) | AWS 托管存储 (对用户透明) |
| 记忆提取 | **手动** — Agent/Hook 决定 | **自动** — LLM 提取事实 | **自动** — 4 种内置策略 |
| 检索方式 | 名称匹配 + 全图读取 | 语义向量搜索 + 图谱遍历 | 语义搜索 + namespace 过滤 |
| LLM 依赖 | 无 (纯数据存取) | 必须 (自带或 Ollama) | 内置 (AWS 托管 LLM) |
| 部署复杂度 | 零依赖 | 中 (Qdrant + LLM) | 低 (全托管，API 调用即可) |
| 记忆类型 | 知识图谱 (1种) | 向量 + 图谱 (2种) | 短期 + 语义 + 偏好 + 摘要 + 情景 (5种) |
| 数据主权 | 完全本地 | 完全本地 | AWS 云端 (VPC 隔离) |
| 成本 | 免费 | LLM tokens 成本 | 按量付费 (见定价) |
| 论文 | 无 | 有 (arXiv:2504.19413) | 有 benchmark 数据 |

## 2. 架构对比

### 2.1 Memory MCP Server (当前方案)

```
对话 → agentStop Hook → Agent 手动提取 → create_entities / create_relations
                                              ↓
                                        memory.jsonl (本地 JSON)
                                              ↓
                                   read_graph / search_nodes / open_nodes
```

**数据模型**: 知识图谱 (Entity-Relation)
- Entity: `{name, entityType, observations[]}`
- Relation: `{from, to, relationType}`

**特点**:
- 存储是确定性的，写什么存什么，没有 LLM 中间层
- 检索靠 `search_nodes` (文本匹配) 或 `read_graph` (全量读取)
- 没有向量嵌入，没有语义搜索
- 数据完全透明，一个 JSONL 文件可以直接查看/编辑

### 2.2 Mem0 OSS (Local Mode)

```
对话 → m.add(messages, user_id) → LLM 提取事实 → 向量相似度查重
                                                      ↓
                                            ADD / UPDATE / DELETE / NOOP
                                                      ↓
                                              Qdrant (向量存储)
                                              Neo4j  (图谱存储，可选)
                                                      ↓
                                            m.search(query, user_id)
                                            → 语义向量检索 + 图谱遍历
```

**核心流程 (来自 Mem0 论文)**:

1. **提取阶段 (Extraction)**: LLM 从对话中自动提取事实性记忆
2. **更新阶段 (Update)**: 对每条新事实，检索 top-s 相似记忆，LLM 决定操作:
   - `ADD` — 全新信息，直接入库
   - `UPDATE` — 补充已有记忆
   - `DELETE` — 新信息与旧记忆矛盾，删除旧的
   - `NOOP` — 已存在或不相关，跳过

**这是 Mem0 最核心的差异化能力**: 自动去重和冲突解决。

### 2.3 AWS Bedrock AgentCore Memory

```
对话 → save_event (短期记忆) → 异步提取流水线 → 多策略并行处理
                                                      ↓
                                    ┌─────────┬──────────┬──────────┬──────────┐
                                    ↓         ↓          ↓          ↓          ↓
                                 语义记忆   偏好记忆    摘要记忆   情景记忆   自定义策略
                                    ↓         ↓          ↓          ↓          ↓
                                              合并 (Consolidation)
                                    ADD / UPDATE / NO-OP (旧记忆标记 INVALID)
                                                      ↓
                                              AWS 托管向量存储
                                                      ↓
                                         retrieve_memory_records(query)
                                         → 语义搜索 + namespace 过滤
```

**五种记忆类型**:

1. **短期记忆 (Short-term)**: 会话内的逐轮交互上下文，TTL 最长 365 天
2. **语义记忆 (Semantic)**: 从对话中提取事实和知识
   - 例: "客户公司在西雅图、奥斯汀、波士顿有 500 名员工"
3. **偏好记忆 (Preference)**: 捕获显式和隐式偏好
   - 例: `{"preference": "偏好用 Python 开发", "categories": ["programming"], "context": "..."}`
4. **摘要记忆 (Summary)**: 按主题生成会话摘要，结构化 XML 格式
   - 例: `<topic="MUI TextareaAutosize 修复"> 开发者成功修复了... </topic>`
5. **情景记忆 (Episodic)**: 记录 Agent 的完整推理路径和经验教训 (**独有**)
   - 包含: 目标、推理步骤、工具调用、结果、反思
   - 支持跨情景反思 (Cross-episodic Reflection)，从多次经验中提炼通用策略

**AgentCore 最核心的差异化能力**: 情景记忆 + 反思机制。不只记住"知道什么"，还记住"怎么做到的"。

**合并机制**: 与 Mem0 类似，使用 LLM 判断 ADD/UPDATE/NO-OP，旧记忆标记为 INVALID 而非物理删除（支持审计追溯）。

## 3. 关键能力对比

### 3.1 记忆写入

| 能力 | Memory MCP | Mem0 OSS | AgentCore Memory |
|------|-----------|----------|------------------|
| 写入方式 | 手动调用 API | `m.add()` 自动提取 | `save_event()` + 异步提取 |
| 事实提取 | Agent 自行判断 | LLM 自动抽取 | 4 种内置策略并行提取 |
| 去重 | 无 (靠 Agent 自觉) | 自动 (向量相似度 + LLM) | 自动 (语义合并 + LLM) |
| 冲突解决 | 无 (新旧共存) | 自动 UPDATE/DELETE | 自动 UPDATE，旧记忆标记 INVALID |
| 偏好提取 | 无专门机制 | 无专门机制 | 专用 Preference 策略 |
| 情景/经验记忆 | ❌ | ❌ | ✅ Episodic + Reflection |
| 自定义提取逻辑 | N/A (手动) | 可自定义 prompt | 支持 override prompt + 自定义模型 |
| 写入成本 | 零 | LLM tokens | $0.25/千事件 + LLM 推理费 |
| 提取延迟 | 即时 | 同步 (秒级) | 异步 (20-40 秒) |

**举例**: 用户先说"我喜欢 Python"，后来说"我现在更喜欢 Rust 了"

- **Memory MCP**: 两条 observation 共存，除非 Agent 主动删旧的
- **Mem0**: 自动识别冲突，UPDATE 为"用户现在更喜欢 Rust"
- **AgentCore**: Preference 策略自动提取偏好变化，旧偏好标记 INVALID，新偏好生效

### 3.2 记忆检索

| 能力 | Memory MCP | Mem0 OSS | AgentCore Memory |
|------|-----------|----------|------------------|
| 语义搜索 | ❌ 文本匹配 | ✅ 向量嵌入 | ✅ 向量嵌入 |
| 图谱遍历 | ❌ 只能读全图 | ✅ 多跳推理 | ❌ 无图谱 |
| 过滤器 | entity name | user_id, metadata | namespace 层级过滤 |
| 多用户隔离 | 无原生支持 | user_id 隔离 | namespace 隔离 |
| 检索延迟 | 即时 (文件读取) | ~200ms | ~200ms |
| 检索精度 | 低 | 高 | 高 |
| 情景检索 | ❌ | ❌ | ✅ 按意图匹配历史经验 |

### 3.3 记忆类型对比

| 记忆类型 | Memory MCP | Mem0 OSS | AgentCore Memory |
|----------|-----------|----------|------------------|
| 短期 (会话内) | ❌ | ❌ | ✅ 原生支持，TTL 最长 365 天 |
| 语义 (事实) | ✅ 手动 observations | ✅ 自动提取 | ✅ Semantic 策略 |
| 偏好 | ❌ | ❌ 无专门机制 | ✅ Preference 策略 |
| 摘要 | ❌ | ❌ | ✅ Summary 策略 |
| 图谱 (关系) | ✅ 手动 relations | ✅ 自动提取 | ❌ |
| 情景 (经验) | ❌ | ❌ | ✅ Episodic 策略 |
| 反思 (跨经验学习) | ❌ | ❌ | ✅ Reflection 模块 |

## 4. 部署复杂度对比

### Memory MCP (当前方案) — 零依赖
```json
// mcp.json — 配置即完成
{
  "mcpServers": {
    "memory": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-memory"],
      "env": { "MEMORY_FILE_PATH": "Kiro-IDE-Data-Agent/memory.jsonl" }
    }
  }
}
```

### Mem0 OSS — 中等复杂度
```python
# 方案 A: 最简 (需要 OpenAI API key)
pip install mem0ai
export OPENAI_API_KEY="sk-..."

from mem0 import Memory
m = Memory()  # 默认用 Qdrant in-memory + OpenAI
```

```python
# 方案 B: 完全本地 (Ollama + Qdrant)
# 需要运行: Qdrant 服务 + Ollama + 模型 (+ Neo4j 可选)
config = {
    "vector_store": {"provider": "qdrant", "config": {"host": "localhost", "port": 6333}},
    "llm": {"provider": "ollama", "config": {"model": "llama3.1:latest"}},
    "embedder": {"provider": "ollama", "config": {"model": "nomic-embed-text:latest"}}
}
m = Memory.from_config(config)
```

### AgentCore Memory — 全托管
```python
# 只需 AWS 账号 + SDK
pip install bedrock-agentcore-memory

from bedrock_agentcore.memory import MemoryClient

client = MemoryClient(memory_id="my-memory-store", region="us-east-1")

# 写入短期记忆
client.save_event(session_id="session-1", actor_id="user-123",
                  event_data={"role": "user", "content": "我喜欢 Python"})

# 长期记忆自动异步提取，无需额外操作

# 检索
results = client.retrieve_memory_records(
    namespace="my-app/users/user-123",
    query="编程语言偏好"
)
```
- 无需管理数据库、向量存储、LLM 推理
- 需要 AWS 账号和网络连接
- 数据在 AWS 云端 (VPC 隔离可选)

## 5. 性能数据

### Mem0 (来自 Mem0 论文, LOCOMO benchmark)

| 方法 | 记忆 tokens | 搜索延迟 p95 | 总延迟 p95 | 整体 J 分数 |
|------|------------|-------------|-----------|------------|
| Full-context | 26,031 | - | 17.1s | 72.9% |
| RAG (最佳) | 256×2 | 0.7s | 1.9s | 61.0% |
| **Mem0** | **1,764** | **0.2s** | **1.4s** | **66.9%** |
| **Mem0 + Graph** | **3,616** | **0.7s** | **2.6s** | **68.4%** |

### AgentCore Memory (来自 AWS 官方 benchmark)

| 记忆类型 | 数据集 | 正确率 | 压缩率 |
|----------|--------|--------|--------|
| RAG 基线 (全量历史) | LoCoMo | 77.7% | 0% |
| Semantic Memory | LoCoMo | 70.6% | 89% |
| RAG 基线 | LongMemEval | 75.2% | 0% |
| Semantic Memory | LongMemEval | 73.6% | 94% |
| RAG 基线 | PrefEval | 51.0% | 0% |
| Preference Memory | PrefEval | **79.0%** | 68% |
| Summary Memory | PolyBench-QA | **83.0%** | 95% |

**AgentCore 关键发现**:
- 语义记忆在 LoCoMo 上压缩率 89%，正确率仅降 7 个百分点
- **偏好记忆在 PrefEval 上比 RAG 基线高 28 个百分点** — 专用策略的价值
- 摘要记忆压缩率 95%，正确率 83% — 适合长对话场景
- 检索延迟 ~200ms，提取+合并 20-40 秒 (异步)

### Episodic Memory (来自 τ2-bench)

| 方法 | Retail Pass^1 | Retail Pass^3 | Airline Pass^1 | Airline Pass^3 |
|------|-------------|-------------|---------------|---------------|
| 无记忆基线 | 65.8% | 42.1% | 47.0% | 24.0% |
| 情景记忆 (ICL) | 69.3% | 43.4% | **55.0%** | **43.0%** |
| 反思记忆 | **77.2%** | **55.7%** | 58.0% | 41.0% |

**情景记忆的独特价值**: 反思记忆在零售场景 Pass^3 提升 13.6%，情景记忆在航空场景 Pass^3 提升 19%。

## 6. 成本对比

| 维度 | Memory MCP | Mem0 OSS | AgentCore Memory |
|------|-----------|----------|------------------|
| 基础设施 | 免费 | Qdrant/Neo4j 运维成本 | 无 (全托管) |
| 写入 | 免费 | LLM tokens (每次 add) | $0.25/千事件 (短期) |
| 存储 | 免费 (本地文件) | 磁盘空间 | $0.75/千条记忆/月 (内置策略) |
| 检索 | 免费 | 免费 (本地) | $0.50/千次检索 |
| LLM 推理 | 无 | 自付 (OpenAI/Ollama) | 内置策略已含；自定义策略自付 |
| 月成本估算 (100 条记忆) | **$0** | **~$1-5** (LLM tokens) | **~$1-3** |
| 月成本估算 (10k 条记忆) | **$0** | **~$50-100** | **~$10-30** |

> AgentCore 新用户有 $200 Free Tier 额度。

## 7. 各方案独有优势

### Memory MCP 独有
- **零成本、零依赖**: 不需要任何外部服务
- **完全透明**: JSONL 文件可直接查看、编辑、Git 版本控制
- **确定性**: 写什么存什么，没有 LLM 提取的不确定性
- **与 Kiro 深度集成**: agentStop Hook 自动触发

### Mem0 独有
- **知识图谱 + 向量双存储**: 唯一同时支持语义搜索和多跳关系推理
- **完全本地可控**: Ollama + Qdrant + Neo4j 全栈本地化
- **开源社区最大**: 47k stars，生态最丰富
- **MCP Server 生态**: 官方和社区都有 MCP 封装

### AgentCore Memory 独有
- **情景记忆 (Episodic Memory)**: 记录 Agent 的完整推理路径、工具调用、结果和反思
- **跨情景反思 (Reflection)**: 从多次经验中提炼通用策略，Agent 能"学习"
- **5 种专用记忆策略**: 语义/偏好/摘要/情景/自定义，各有专门的提取逻辑
- **全托管**: 无需管理数据库、向量存储、LLM 推理基础设施
- **企业级**: VPC/PrivateLink/CloudFormation/IAM，审计追溯 (旧记忆标记 INVALID 而非删除)
- **Namespace 层级**: `app/team/user` 结构化记忆隔离
- **短期记忆原生支持**: 会话内上下文管理，TTL 可配

## 8. 对 IDE Data Agent 项目的适用性分析

| 场景 | 推荐 | 理由 |
|------|------|------|
| 当前规模 (< 100 条记忆) | **Memory MCP** | 满足需求且零成本 |
| 记忆量增长到 500+ | Mem0 或 AgentCore | 需要语义检索 |
| 需要多跳关系推理 | **Mem0 + Graph** | 唯一支持图谱遍历 |
| 需要 Agent 从经验中学习 | **AgentCore** | 情景记忆 + 反思是独有能力 |
| 需要完全离线/数据主权 | **Mem0 + Ollama** | 全栈本地化 |
| 企业级多用户/多 Agent | **AgentCore** | 全托管 + IAM + namespace |
| 需要偏好追踪 | **AgentCore** | 专用 Preference 策略 |
| 预算敏感 | **Memory MCP** | 免费 |

### 三者的本质定位

```
Memory MCP          Mem0 OSS              AgentCore Memory
"记事本"            "智能笔记"             "学习型助手"
─────────────────────────────────────────────────────────────
手动记录            自动提取+去重           自动提取+去重+反思
文本匹配            语义搜索+图谱           语义搜索+情景回忆
零成本              中等成本               按量付费
本地文件            本地服务               云端托管
```

- **Memory MCP** 是"记事本" — 写入什么就存什么，完全确定性
- **Mem0** 是"智能笔记" — 自动整理、去重、关联，但只记"知道什么"
- **AgentCore** 是"学习型助手" — 不仅记住知识，还记住经验和教训，能从中学习

## 9. 总结

三者解决的是记忆管理的不同层次:

1. **Memory MCP**: 存储层 — 提供最基础的图谱存取能力，记忆管理完全由 Agent 控制
2. **Mem0**: 智能存储层 — 在存储之上加了 LLM 驱动的提取、去重、冲突解决流水线
3. **AgentCore**: 认知层 — 在智能存储之上加了多种专用策略 + 情景记忆 + 反思学习

对于当前的 IDE Data Agent 项目，**Memory MCP 仍然是最合适的选择** — 项目规模小、记忆量可控、与 Kiro Hook 集成良好。

如果未来需要升级:
- **需要语义搜索 + 图谱**: 引入 Mem0
- **需要 Agent 学习能力 + 企业级**: 引入 AgentCore Memory
- 三者可以共存互补，不是非此即彼的选择

---

**参考来源**:
- [Mem0 论文 (arXiv:2504.19413)](https://arxiv.org/html/2504.19413)
- [Mem0 OSS 文档](https://docs.mem0.ai/open-source/overview)
- [Mem0 Graph Memory](https://docs.mem0.ai/open-source/graph_memory/overview)
- [Mem0 Memory Operations](https://docs.mem0.ai/core-concepts/memory-operations)
- [OpenMemory MCP](https://mem0.ai/blog/introducing-openmemory-mcp/)
- [Mem0 + Ollama 本地部署](https://docs.mem0.ai/examples/mem0-with-ollama)
- [AgentCore Memory 文档](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/memory.html)
- [AgentCore Long-term Memory Deep Dive](https://aws.amazon.com/blogs/machine-learning/building-smarter-ai-agents-agentcore-long-term-memory-deep-dive/)
- [AgentCore Episodic Memory](https://aws.amazon.com/blogs/machine-learning/build-agents-to-learn-from-experiences-using-amazon-bedrock-agentcore-episodic-memory/)
- [AgentCore Memory 定价](https://aws.amazon.com/bedrock/agentcore/pricing/)

*Content was rephrased for compliance with licensing restrictions*
