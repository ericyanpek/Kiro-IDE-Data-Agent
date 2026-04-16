---
inclusion: auto
---

# SQL 查询与数据分析规范

本文件定义 Agent 在生成 SQL 查询和数据分析时应遵循的规范。

## SQL 生成规范

### 基本原则
1. **只读查询**: 只生成 SELECT 语句，禁止 INSERT / UPDATE / DELETE / DROP / TRUNCATE
2. **表名准确**: 当前环境只有 `orders` 一张表，不要臆造不存在的表
3. **字段名准确**: 严格使用 `order_id`, `order_date`, `channel`, `category`, `amount`, `status` 这六个字段
4. **中文枚举值精确匹配**: 渠道和品类的值是中文，必须完全匹配（如 `'电子产品'` 不是 `'电子'`）
5. **收入计算默认过滤退款**: 除非用户明确要求，收入相关查询默认加 `WHERE status = '已完成'`

### 查询风格
- 使用有意义的别名: `AS revenue` 而非 `AS col1`
- 金额字段保留两位小数或取整: `ROUND(AVG(amount), 2)`
- 日期排序默认升序: `ORDER BY order_date ASC`
- 大查询使用 CTE 提高可读性

### DuckDB 特有语法
- 支持 `PIVOT` / `UNPIVOT` 语法
- 支持 `QUALIFY` 子句（窗口函数过滤）
- 支持 `EXCLUDE` / `REPLACE` 列选择修饰符
- 列表聚合: `LIST(column)`, `STRING_AGG(column, ',')`
- 近似聚合: `APPROX_COUNT_DISTINCT(column)`

## 分析输出规范

### 数值格式化
- 金额: `¥1,234.56` 或 `¥1,235`（大数取整）
- 百分比: `15.2%`（保留一位小数）
- 订单量: `1,234`（千分位分隔）

### 图表建议
- 时间趋势 → 折线图或柱状图 + 移动均线
- 占比分析 → 环形图（Pie with hole）
- 对比分析 → 水平柱状图
- 交叉分析 → 热力图
- 分布分析 → 直方图或箱线图

### Notebook 生成规范
- 使用 DuckDB Python API: `conn.execute(sql).fetchdf()` 返回 DataFrame
- 可视化优先用 Plotly（交互式），备选 matplotlib（静态）
- 控件用 ipywidgets，支持动态筛选
- 每个分析模块包含: Markdown 说明 → SQL/代码 → 图表 → 结论

## 业务术语映射

当用户使用以下自然语言时，映射到对应的 SQL 逻辑：

| 用户说 | SQL 含义 |
|--------|----------|
| "收入" / "营收" / "销售额" | `SUM(amount) WHERE status = '已完成'` |
| "GMV" / "总交易额" | `SUM(amount)`（含退款） |
| "客单价" / "平均订单金额" | `AVG(amount)` |
| "退款率" | `SUM(退款金额) / SUM(总金额) * 100` |
| "转化" / "完成率" | `COUNT(已完成) / COUNT(*) * 100` |
| "日均" | 按 `order_date` 分组后取 `AVG` |
| "环比" | 当前周期 vs 上一周期的变化率 |
| "同比" | 当前周期 vs 去年同期（本数据集仅90天，不适用） |
| "Top N" | `ORDER BY ... DESC LIMIT N` |
| "趋势" | 按 `order_date` 分组的时间序列 |
| "分布" | 按某维度 `GROUP BY` 的聚合 |
| "交叉分析" | 多维度 `GROUP BY` 或 `PIVOT` |
