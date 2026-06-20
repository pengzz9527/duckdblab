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

在数据分析的日常工作中，我们经常需要从各种 Web API 获取数据——天气预报、股票行情、社交媒体指标、电商平台数据等等。传统做法是写 Python 脚本调用 `requests` 库，解析 JSON，然后导入 Pandas 或写入数据库。但有了 DuckDB 的 httpfs 扩展和内置 JSON 函数，这一切都可以**纯 SQL 完成**。

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

首先安装 DuckDB 并加载 httpfs 扩展：

```sql
-- 安装并加载 httpfs 扩展
INSTALL httpfs;
LOAD httpfs;

-- 验证扩展是否加载成功
SELECT * FROM duckdb_extensions() WHERE extension_name = 'httpfs';
```
-- 假设 API 返回的是包含 orders 数组的 JSON
WITH parsed_orders AS (
    SELECT 
        id,
        customer_name,
        status,
        total_amount
    FROM read_json_auto('https://jsonplaceholder.typicode.com/posts', auto_detect=true)
    LIMIT 10
)
SELECT 
    status,
    COUNT(*) AS order_count,
    ROUND(SUM(total_amount::DOUBLE), 2) AS total
FROM parsed_orders
GROUP BY status;
```

关键点：
- `read_json_auto()` 自动检测 JSON 结构并返回关系型表格
- `read_csv_auto()` 自动检测 CSV 格式
- `read_parquet()` 直接读取 Parquet 文件
- 所有函数都支持 HTTP/HTTPS URL，无需下载文件
- 使用 `auto_detect=true` 自动推断列类型

## 核心功能四：直接查询远程 Parquet/CSV 文件

DuckDB 最强大的能力之一是直接查询云存储中的数据文件，无需下载：

```sql
-- 直接读取远程 Parquet 文件（纽约出租车数据，296万行）
SELECT COUNT(*) FROM read_parquet('https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2024-01.parquet');

-- 读取远程 CSV（自动检测分隔符）
SELECT COUNT(*) FROM read_csv_auto('https://raw.githubusercontent.com/vincentarelbundock/Rdatasets/master/datasets.csv');

-- 读取远程 JSON 并分页分析
SELECT 
    passenger_count,
    COUNT(*) AS trip_count,
    ROUND(AVG(total_amount), 2) AS avg_amount
FROM read_parquet('https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2024-01.parquet')
GROUP BY passenger_count
ORDER BY trip_count DESC;
```

## 实战项目：构建自动化的竞品监控仪表盘

结合多个数据源，构建一个自动化的竞品监控系统：

```sql
-- 步骤1：从 GitHub API 获取仓库数据
CREATE TEMP TABLE github_data AS
SELECT 
    id,
    name AS repo_name,
    stargazers_count AS stars,
    language,
    updated_at
FROM read_json_auto('https://jsonplaceholder.typicode.com/posts', auto_detect=true)
LIMIT 10;

-- 步骤2：从另一个 API 获取评论数据
CREATE TEMP TABLE review_data AS
SELECT 
    id AS review_id,
    title AS product_name,
    body AS review_text
FROM read_json_auto('https://jsonplaceholder.typicode.com/comments', auto_detect=true)
LIMIT 20;

-- 步骤3：JOIN 分析
SELECT 
    g.repo_name,
    g.stars,
    COUNT(r.review_id) AS review_count
FROM github_data g
LEFT JOIN review_data r ON g.id = r.id
GROUP BY g.repo_name, g.stars
ORDER BY g.stars DESC;
```

性能优化技巧

### 1. 缓存 API 响应

频繁查询同一 API 会很浪费。可以用 DuckDB 的临时表来缓存：

```sql
-- 缓存 API 响应到临时表
CREATE TEMP TABLE cached_github_repos AS
SELECT 
    id,
    name AS repo_name,
    stargazers_count,
    language,
    updated_at
FROM read_json_auto('https://jsonplaceholder.typicode.com/posts', auto_detect=true);

-- 后续分析直接查询缓存表（零网络开销）
SELECT
    repo_name,
    stargazers_count AS stars,
    language
FROM cached_github_repos
WHERE stargazers_count > 1000
ORDER BY stars DESC;
```

### 2. 并行读取多个文件

```sql
-- 并行读取 Parquet 文件（DuckDB 自动并行化）
SELECT 
    passenger_count,
    COUNT(*) AS trip_count,
    ROUND(AVG(total_amount), 2) AS avg_amount
FROM read_parquet('https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2024-01.parquet')
GROUP BY passenger_count
ORDER BY trip_count DESC;
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
