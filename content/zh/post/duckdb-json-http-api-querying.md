---
title: "DuckDB 直接查询 Web API：HTTP 扩展 + JSON 函数实战"
slug: "duckdb-json-http-api-querying"
date: 2026-06-20
draft: false
description: "无需编写任何 Python 代码，直接用 DuckDB 的 HTTP 扩展和 JSON 函数查询 REST API，将网页数据转化为关系型表格进行分析。附完整 SQL 示例和变现建议。"
tags: ["DuckDB", "HTTP 扩展", "JSON", "API 查询", "数据工程", "SQL"]
categories: ["实战教程"]
image: /images/posts/duckdb-json-http-api-querying/architecture.png
---

# DuckDB 直接查询 Web API：HTTP 扩展 + JSON 函数实战

在数据分析的日常工作中，我们经常需要从各种 Web API 获取数据——天气预报、股票行情、社交媒体指标、电商平台数据等等。传统做法是写 Python 脚本调用 `requests` 库，解析 JSON，然后导入 Pandas 或写入数据库。但有了 DuckDB 的 HTTP 扩展和内置 JSON 函数，这一切都可以**纯 SQL 完成**。

本文将带你从零开始，掌握用 DuckDB 直接查询 Web API 的完整技能栈。

## 为什么选择 DuckDB 查询 API？

| 维度 | 传统 Python 方案 | DuckDB HTTP 方案 |
|------|-----------------|-----------------|
| 代码量 | 20-50 行 Python | 1 条 SQL |
| 依赖 | requests, pandas, json | 仅 DuckDB |
| 性能 | 逐行解析，内存占用高 | 向量化列式处理 |
| 可组合性 | 需手动拼接 DataFrame | SQL JOIN/WHERE/GROUP BY 原生支持 |
| 学习曲线 | Python + API 文档 | 只需 SQL 基础 |

对于已经掌握 SQL 的数据分析师和业务人员来说，DuckDB 的 HTTP 扩展大大降低了获取和分析外部数据的门槛。

## 环境准备

首先安装 DuckDB 并加载 HTTP 扩展：

```sql
-- 启动 DuckDB
$ duckdb

-- 安装并加载 HTTP 扩展
INSTALL http;
LOAD http;

-- 查看可用函数
SHOW ALL FUNCTIONS LIKE '%http%';
```

## 核心功能一：http_get() 查询 REST API

DuckDB 提供了 `http_get()` 函数，可以直接发起 HTTP GET 请求并返回响应内容作为 BLOB 类型。

### 示例：查询 GitHub API

```sql
-- 加载 HTTP 扩展
INSTALL http;
LOAD http;

-- 直接查询 GitHub 用户信息
SELECT 
    json_extract_scalar(value, '$.login') AS username,
    json_extract_scalar(value, '$.avatar_url') AS avatar,
    json_extract_scalar(value, '$.public_repos') AS repos,
    json_extract_scalar(value, '$.followers') AS followers
FROM json_each(
    http_get(
        'https://api.github.com/repos/duckdb/duckdb',
        {'headers': {'Accept': 'application/vnd.github.v3+json'}}
    ),
    '$.contributors'
) AS t(value);
```

这段 SQL 做了以下几件事：
1. `http_get()` 向 GitHub API 发起请求，获取仓库贡献者列表
2. `json_each()` 将 JSON 数组展开为多行
3. `json_extract_scalar()` 从每个 JSON 对象中提取字段

### 示例：查询公开天气 API

```sql
-- 使用 Open-Meteo 免费天气 API（无需 API Key）
SELECT 
    json_extract_scalar(value, '$.time') AS date,
    json_extract_scalar(value, '$.weather_code') AS weather_code,
    json_extract_scalar(value, '$.temperature_2m_max') AS temp_max,
    json_extract_scalar(value, '$.temperature_2m_min') AS temp_min,
    json_extract_scalar(value, '$.precipitation_sum') AS precipitation
FROM json_each(
    http_get('https://archive-api.open-meteo.com/v1/archive?latitude=39.9&longitude=116.3&start_date=2025-01-01&end_date=2025-01-31&daily=temperature_2m_max,temperature_2m_min,precipitation_sum&timezone=Asia/Shanghai'),
    '$.daily.time'
) AS t(time);
```

## 核心功能二：http_post() 提交数据

除了 GET 请求，`http_post()` 支持 POST 方法，可以携带请求体和自定义 Header：

```sql
-- POST 请求示例：提交数据到 webhook
SELECT http_post(
    'https://hooks.slack.com/services/YOUR/WEBHOOK/URL',
    '{"text":"DuckDB 报告已生成"}',
    {'headers': {'Content-Type': 'application/json'}}
);

-- PUT 请求（通过 http_post 模拟）
SELECT http_post(
    'https://api.example.com/resource/123',
    '{"name":"updated","status":"active"}',
    {'method': 'PUT', 'headers': {'Content-Type': 'application/json'}}
);
```

## 核心功能三：嵌套 JSON 解析

现实中的 API 响应往往包含多层嵌套的 JSON。DuckDB 提供了丰富的 JSON 函数来处理这种情况：

```sql
-- 解析多层嵌套的电商 API 响应
WITH api_response AS (
    SELECT http_get(
        'https://api.example.com/orders?limit=100'
    ) AS raw_data
),
parsed_json AS (
    SELECT 
        json_extract(raw_data, '$.orders') AS orders_json
    FROM api_response
),
order_items AS (
    SELECT 
        json_extract_scalar(order_val, '$.id') AS order_id,
        json_extract_scalar(order_val, '$.customer.name') AS customer_name,
        json_extract_scalar(order_val, '$.customer.email') AS customer_email,
        json_extract_scalar(order_val, '$.status') AS status,
        json_extract_scalar(order_val, '$.total') AS total_amount
    FROM parsed_json,
    json_each(parsed_json.orders_json) AS t(order_val)
)
SELECT 
    status,
    COUNT(*) AS order_count,
    ROUND(SUM(total_amount::DOUBLE), 2) AS total_revenue,
    ROUND(AVG(total_amount::DOUBLE), 2) AS avg_order_value
FROM order_items
GROUP BY status
ORDER BY total_revenue DESC;
```

关键点：
- `json_extract()` 返回 JSON 值（可用于进一步解析）
- `json_extract_scalar()` 返回字符串标量
- `json_each()` 将 JSON 数组展开为多行
- `json_object_keys()` 获取 JSON 对象的键名

## 核心功能四：直接查询远程 Parquet/CSV 文件

DuckDB 最强大的能力之一是直接查询云存储中的数据文件，无需下载：

```sql
-- 直接从 URL 读取 Parquet 文件
SELECT * FROM read_parquet('https://example.com/data/dataset.parquet');

-- 读取多个文件（glob 模式）
SELECT COUNT(*) FROM read_parquet('https://storage.example.com/logs/*.parquet');

-- 读取远程 CSV（自动检测分隔符）
SELECT * FROM read_csv_auto('https://example.com/data/sales.csv');

-- 读取远程 JSON 文件
SELECT * FROM read_json_auto('https://example.com/data/users.json');

-- 组合：从 API 获取 Parquet 并分析
SELECT 
    region,
    SUM(revenue) AS total_revenue,
    AVG(order_count) AS avg_orders
FROM read_parquet('https://api.analytics.example.com/export?format=parquet')
WHERE date >= '2025-01-01'
GROUP BY region
ORDER BY total_revenue DESC;
```

## 实战项目：构建自动化的竞品监控仪表盘

下面是一个完整的实战案例——监控竞争对手的产品评分变化：

```sql
-- Step 1: 从多个数据源聚合
WITH competitor_data AS (
    -- 来源1: 应用商店评论 API
    SELECT 
        json_extract_scalar(item, '$.product_name') AS product,
        json_extract_scalar(item, '$.rating') AS rating,
        json_extract_scalar(item, '$.review_date') AS review_date,
        json_extract_scalar(item, '$.source') AS source
    FROM json_each(
        http_get('https://api.review-tracker.com/v1/products?ids=101,102,103'),
        '$.reviews'
    ) AS t(item)
),
-- 来源2: 社交媒体提及
social_mentions AS (
    SELECT 
        json_extract_scalar(m, '$.mention_text') AS text,
        json_extract_scalar(m, '$.sentiment') AS sentiment,
        json_extract_scalar(m, '$.platform') AS platform,
        json_extract_scalar(m, '$.timestamp') AS mentioned_at
    FROM json_each(
        http_get('https://api.social-tracker.com/v1/mentions?q=competitor'),
        '$.results'
    ) AS t(m)
),
-- 合并分析
analysis AS (
    SELECT 
        product,
        AVG(rating::DOUBLE) AS avg_rating,
        COUNT(*) AS review_count,
        MIN(review_date) AS first_review,
        MAX(review_date) AS last_review
    FROM competitor_data
    GROUP BY product
)
-- 最终输出：按评分排序的竞品列表
SELECT 
    a.product,
    a.avg_rating,
    a.review_count,
    a.first_review,
    a.last_review,
    CASE 
        WHEN a.avg_rating >= 4.5 THEN '🟢 强势'
        WHEN a.avg_rating >= 4.0 THEN '🟡 稳定'
        ELSE '🔴 预警'
    END AS status
FROM analysis a
ORDER BY a.avg_rating DESC;
```

这个查询展示了 DuckDB 在处理多源数据时的优势：
1. 无需编写 Python 循环来获取多个 API 数据
2. 所有数据在 SQL 层面即可 JOIN 和聚合
3. 查询结果可以直接导出为 Parquet 供后续使用

## 性能优化技巧

### 1. 缓存 HTTP 响应

频繁查询同一 API 会很浪费。可以用 DuckDB 的临时表来缓存：

```sql
-- 缓存 API 响应到临时表
CREATE TEMP TABLE cached_github_repos AS
SELECT * FROM json_each(
    http_get('https://api.github.com/users/duckdb/repos'),
    '$[*]'
) AS t(value);

-- 后续分析直接查询缓存
SELECT 
    json_extract_scalar(value, '$.name') AS repo_name,
    json_extract_scalar(value, '$.stargazers_count') AS stars,
    json_extract_scalar(value, '$.language') AS language
FROM cached_github_repos
WHERE json_extract_scalar(value, '$.stargazers_count')::BIGINT > 1000
ORDER BY stars DESC;
```

### 2. 并行读取多个文件

```sql
-- 并行读取多个 Parquet 文件（DuckDB 自动并行化）
SELECT 
    file_name,
    COUNT(*) AS row_count,
    SUM(size_bytes) AS total_size
FROM parquet_metadata('s3://bucket/data/*.parquet')
GROUP BY file_name
ORDER BY total_size DESC;
```

### 3. 使用谓词下推过滤

```sql
-- 直接在读取时过滤，减少数据传输
SELECT * FROM read_parquet('https://storage.example.com/large-dataset.parquet')
WHERE date >= '2025-06-01' AND category = 'electronics';
```

## 架构图

下面是 DuckDB 查询 Web API 的整体架构流程：

![DuckDB HTTP + JSON 架构图](/images/posts/duckdb-json-http-api-querying/diagram.png)

![数据管道架构](/images/posts/duckdb-json-http-api-querying/architecture.png)

## 与传统工具对比总结

| 特性 | DuckDB HTTP | Python + requests | Excel Power Query | Tableau Data Connectors |
|------|------------|-------------------|-------------------|------------------------|
| 纯 SQL 查询 | ✅ | ❌ | 部分 | ❌ |
| 嵌套 JSON 解析 | ✅ | ✅ | 有限 | ❌ |
| 并行读取 | ✅ 自动 | 需多线程 | ❌ | ❌ |
| 大数据集处理 | ✅ 列式引擎 | 内存受限 | ❌ | 受限于连接器 |
| 零依赖部署 | ✅ 单文件 | pip install | ✅ | ✅ |
| 学习成本 | SQL 基础 | Python 编程 | 中等 | 低 |
| 变现友好度 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ | ⭐⭐ |

## 变现建议：如何用这项技能赚钱

掌握 DuckDB 的 HTTP 扩展和 JSON 处理能力后，你可以从以下几个方向实现变现：

### 1. 自动化数据报告服务（月收入 ¥2,000-10,000）

为中小企业提供每日/每周自动数据报告服务。例如：
- 从电商平台 API 拉取销售数据，自动生成周报
- 从社交媒体 API 抓取品牌提及，生成舆情分析报告
- 从天气 API 获取历史数据，为农业/物流客户提供决策建议

**实施步骤：**
1. 注册 DuckDB Cloud 或使用本地 DuckDB
2. 编写 SQL 脚本从目标 API 拉取数据
3. 使用 `COPY ... TO 'report.csv'` 导出结果
4. 搭配定时任务（cron）自动运行
5. 通过邮件或 Slack 发送报告

### 2. 数据产品 SaaS（月收入 ¥5,000-50,000）

构建面向特定行业的数据产品：
- **房价监控工具**：聚合多个房产网站 API，提供区域价格趋势
- **竞品价格追踪器**：定时抓取电商商品价格和库存
- **自媒体数据看板**：整合 YouTube/TikTok/B站 的多平台数据

**技术栈：** DuckDB (数据处理) + FastAPI (后端) + Streamlit (前端)

### 3. 数据咨询服务（单次 ¥3,000-20,000）

很多企业有数据但不会用。你可以提供：
- API 数据接入方案设计
- 现有数据管道的 DuckDB 迁移优化
- 定制化的数据分析和报表开发

### 4. 在线课程和教程（被动收入）

将你的经验制作成付费课程：
- "用 DuckDB 从零构建数据分析 pipeline"
- "Web API 数据抓取与分析实战"
- "DuckDB JSON 处理高级技巧"

**关键优势：** DuckDB 的 HTTP 扩展让数据获取变得极其简单，你可以在课程中专注于"分析"本身，而不是花大量时间写爬虫代码。

---

**总结：** DuckDB 的 HTTP 扩展和 JSON 函数让你能够用纯 SQL 完成从数据采集到分析的全流程。无论是个人项目还是商业应用，这都是一个强大的技能组合。现在就打开 DuckDB，尝试查询一个你感兴趣的 API 吧！
