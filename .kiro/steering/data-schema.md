---
inclusion: auto
---

# 电商订单数据 Schema 与业务语义

本文件描述 IDE Data Agent 演示环境中的数据表结构、字段含义和业务规则。
Agent 在生成 SQL 查询时应严格参照此 schema，确保字段名、数据类型和业务逻辑正确。

## 数据引擎

- **引擎**: DuckDB（嵌入式进程内分析引擎）
- **连接方式**: `duckdb.connect()` 内存数据库，无需外部服务
- **数据规模**: 5,000 条模拟订单，覆盖 90 天（2025-01-01 ~ 2025-03-31）

## 表结构

### orders（订单主表）

```sql
CREATE TABLE orders AS
SELECT
    row_number() OVER ()                                    AS order_id,     -- 订单ID，自增整数，主键
    '2025-01-01'::DATE + INTERVAL (floor(random()*90)::INT) DAY AS order_date,  -- 下单日期，DATE 类型，范围 2025-01-01 ~ 2025-03-31
    CASE floor(random()*4)::INT
        WHEN 0 THEN '直接访问'
        WHEN 1 THEN '搜索引擎'
        WHEN 2 THEN '社交媒体'
        ELSE '付费广告'
    END                                                     AS channel,      -- 流量渠道，中文枚举
    CASE floor(random()*3)::INT
        WHEN 0 THEN '电子产品'
        WHEN 1 THEN '服装'
        ELSE '食品'
    END                                                     AS category,     -- 商品品类，中文枚举
    round(random()*500 + 10, 2)                             AS amount,       -- 订单金额，DECIMAL，范围 10.00 ~ 510.00
    CASE WHEN random() > 0.15 THEN '已完成' ELSE '已退款' END AS status       -- 订单状态，中文枚举
FROM generate_series(1, 5000)
```

### 字段明细

| 字段 | 类型 | 说明 | 枚举值 |
|------|------|------|--------|
| `order_id` | INTEGER | 订单唯一标识，自增主键 | — |
| `order_date` | DATE | 下单日期 | 2025-01-01 ~ 2025-03-31 |
| `channel` | VARCHAR | 流量来源渠道 | `直接访问`、`搜索引擎`、`社交媒体`、`付费广告` |
| `category` | VARCHAR | 商品品类 | `电子产品`、`服装`、`食品` |
| `amount` | DECIMAL | 订单金额（人民币 ¥） | 10.00 ~ 510.00 |
| `status` | VARCHAR | 订单状态 | `已完成`、`已退款` |

## 业务规则与语义

### 渠道（channel）
- **直接访问**: 用户直接输入网址或书签访问
- **搜索引擎**: 通过百度、Google 等搜索引擎进入
- **社交媒体**: 通过微信、微博、抖音等社交平台引流
- **付费广告**: 通过 SEM、信息流广告等付费渠道获客

### 品类（category）
- **电子产品**: 手机、电脑、数码配件等
- **服装**: 男装、女装、鞋帽等
- **食品**: 零食、生鲜、饮品等

### 状态（status）
- **已完成**: 正常完成的订单，约占 85%
- **已退款**: 发生退款的订单，约占 15%
- 计算收入时通常只统计 `status = '已完成'` 的订单
- **退款率** = 已退款订单金额 / 总订单金额 × 100%

### 金额（amount）
- 单位: 人民币（¥）
- 均匀分布在 10 ~ 510 之间，平均客单价约 ¥260
- 格式化显示建议: `¥{amount:,.2f}` 或 `¥{amount:,.0f}`

## 常用查询模式

### 收入分析
```sql
-- 每日收入（仅已完成订单）
SELECT order_date, COUNT(*) AS order_count, SUM(amount) AS revenue
FROM orders WHERE status = '已完成'
GROUP BY order_date ORDER BY order_date;

-- 7日移动均线（用 pandas rolling 或 DuckDB 窗口函数）
SELECT order_date, revenue,
       AVG(revenue) OVER (ORDER BY order_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS ma7
FROM (SELECT order_date, SUM(amount) AS revenue FROM orders WHERE status = '已完成' GROUP BY order_date);
```

### 渠道分析
```sql
-- 各渠道核心指标
SELECT channel,
       COUNT(*) AS order_count,
       SUM(amount) AS revenue,
       AVG(amount) AS avg_amount
FROM orders
GROUP BY channel ORDER BY revenue DESC;
```

### 退款分析
```sql
-- 各渠道退款率
SELECT channel,
       SUM(CASE WHEN status = '已退款' THEN amount ELSE 0 END) / SUM(amount) * 100 AS refund_pct
FROM orders
GROUP BY channel;
```

### 交叉分析
```sql
-- 品类 × 渠道 收入矩阵
SELECT category, channel, SUM(amount) AS revenue
FROM orders WHERE status = '已完成'
GROUP BY category, channel
ORDER BY category, revenue DESC;
```

## DuckDB 语法提示

- 日期字面量: `'2025-01-01'::DATE`
- 日期运算: `+ INTERVAL (n) DAY`
- 随机数: `random()` 返回 0~1 之间的浮点数
- 序列生成: `generate_series(1, N)`
- 字符串比较: 中文值需用单引号，如 `WHERE channel = '直接访问'`
- DuckDB 支持标准 SQL 窗口函数、CTE、PIVOT 等高级语法

## 注意事项

1. 数据为随机生成的模拟数据，每次重新运行 notebook 会产生不同的具体数值
2. 四个渠道和三个品类的数据量大致均匀（随机分布）
3. 查询金额相关指标时注意区分"全部订单"和"已完成订单"
4. 中文字段值在 SQL 中需要精确匹配，注意不要写错
