---
title: "Querying Web APIs Directly with DuckDB: HTTP Extension + JSON Functions in Action"
slug: "duckdb-json-http-api-querying"
date: 2026-06-20
draft: false
description: "Query REST APIs directly with pure SQL using DuckDB's HTTP extension and built-in JSON functions. No Python required. Includes executable examples and monetization tips."
tags: ["DuckDB", "HTTP Extension", "JSON", "API Querying", "Data Engineering", "SQL"]
categories: ["Tutorial"]
---

# Querying Web APIs Directly with DuckDB: HTTP Extension + JSON Functions in Action

In daily data analysis work, we frequently need to fetch data from various Web APIs — weather forecasts, stock quotes, social media metrics, e-commerce data, and more. The traditional approach involves writing Python scripts with the `requests` library, parsing JSON, and importing into Pandas or a database. But with DuckDB's HTTP extension and built-in JSON functions, **all of this can be done in pure SQL**.

This article walks you through mastering the complete skill stack for querying Web APIs directly with DuckDB.

## Why Use DuckDB to Query APIs?

| Dimension | Traditional Python Approach | DuckDB HTTP Approach |
|-----------|---------------------------|---------------------|
| Code Lines | 20-50 lines of Python | 1 SQL statement |
| Dependencies | requests, pandas, json | DuckDB only |
| Performance | Row-by-row parsing, high memory | Vectorized columnar processing |
| Composability | Manual DataFrame joining | Native SQL JOIN/WHERE/GROUP BY |
| Learning Curve | Python + API docs | Basic SQL knowledge |

For data analysts and business users who already know SQL, DuckDB's HTTP extension dramatically lowers the barrier to acquiring and analyzing external data.

## Environment Setup

First, install DuckDB and load the HTTP extension:

```sql
-- Start DuckDB
$ duckdb

-- Install and load the HTTP extension
INSTALL http;
LOAD http;

-- View available functions
SHOW ALL FUNCTIONS LIKE '%http%';
```

## Feature 1: http_get() — Querying REST APIs

DuckDB provides the `http_get()` function, which can directly make HTTP GET requests and return the response content as a BLOB type.

### Example: Querying the GitHub API

```sql
-- Load HTTP extension
INSTALL http;
LOAD http;

-- Directly query GitHub repository information
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

This SQL does the following:
1. `http_get()` makes a request to the GitHub API and retrieves the contributor list
2. `json_each()` expands the JSON array into multiple rows
3. `json_extract_scalar()` extracts fields from each JSON object

### Example: Querying a Public Weather API

```sql
-- Using Open-Meteo free weather API (no API key required)
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

## Feature 2: http_post() — Submitting Data

Beyond GET requests, `http_post()` supports the POST method with request bodies and custom headers:

```sql
-- POST request example: sending data to a webhook
SELECT http_post(
    'https://hooks.slack.com/services/YOUR/WEBHOOK/URL',
    '{"text":"DuckDB report has been generated"}',
    {'headers': {'Content-Type': 'application/json'}}
);

-- PUT request (simulated via http_post)
SELECT http_post(
    'https://api.example.com/resource/123',
    '{"name":"updated","status":"active"}',
    {'method': 'PUT', 'headers': {'Content-Type': 'application/json'}}
);
```

## Feature 3: Nested JSON Parsing

Real-world API responses often contain deeply nested JSON. DuckDB provides a rich set of JSON functions to handle such cases:

```sql
-- Parse deeply nested e-commerce API response
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

Key points:
- `json_extract()` returns a JSON value (usable for further parsing)
- `json_extract_scalar()` returns a string scalar
- `json_each()` expands a JSON array into multiple rows
- `json_object_keys()` retrieves the keys of a JSON object

## Feature 4: Querying Remote Parquet/CSV Files Directly

One of DuckDB's most powerful features is querying cloud-stored data files directly, without downloading them:

```sql
-- Read a Parquet file directly from a URL
SELECT * FROM read_parquet('https://example.com/data/dataset.parquet');

-- Read multiple files (glob pattern)
SELECT COUNT(*) FROM read_parquet('https://storage.example.com/logs/*.parquet');

-- Read remote CSV (auto-detect delimiter)
SELECT * FROM read_csv_auto('https://example.com/data/sales.csv');

-- Read remote JSON file
SELECT * FROM read_json_auto('https://example.com/data/users.json');

-- Combine: query Parquet from an API and analyze
SELECT 
    region,
    SUM(revenue) AS total_revenue,
    AVG(order_count) AS avg_orders
FROM read_parquet('https://api.analytics.example.com/export?format=parquet')
WHERE date >= '2025-01-01'
GROUP BY region
ORDER BY total_revenue DESC;
```

## Practical Project: Building an Automated Competitor Monitoring Dashboard

Here's a complete real-world example — monitoring competitors' product ratings over time:

```sql
-- Step 1: Aggregate from multiple data sources
WITH competitor_data AS (
    -- Source 1: App store review API
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
-- Source 2: Social media mentions
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
-- Combined analysis
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
-- Final output: competitor list sorted by rating
SELECT 
    a.product,
    a.avg_rating,
    a.review_count,
    a.first_review,
    a.last_review,
    CASE 
        WHEN a.avg_rating >= 4.5 THEN '🟢 Strong'
        WHEN a.avg_rating >= 4.0 THEN '🟡 Stable'
        ELSE '🔴 Alert'
    END AS status
FROM analysis a
ORDER BY a.avg_rating DESC;
```

This query showcases DuckDB's advantages in handling multi-source data:
1. No need to write Python loops to fetch data from multiple APIs
2. All data can be JOINed and aggregated at the SQL level
3. Query results can be exported to Parquet for downstream use

## Performance Optimization Tips

### 1. Cache HTTP Responses

Frequently querying the same API is wasteful. Use DuckDB's temporary tables to cache:

```sql
-- Cache API response to a temporary table
CREATE TEMP TABLE cached_github_repos AS
SELECT * FROM json_each(
    http_get('https://api.github.com/users/duckdb/repos'),
    '$[*]'
) AS t(value);

-- Subsequent analysis queries the cache directly
SELECT 
    json_extract_scalar(value, '$.name') AS repo_name,
    json_extract_scalar(value, '$.stargazers_count') AS stars,
    json_extract_scalar(value, '$.language') AS language
FROM cached_github_repos
WHERE json_extract_scalar(value, '$.stargazers_count')::BIGINT > 1000
ORDER BY stars DESC;
```

### 2. Parallel Reading of Multiple Files

```sql
-- Parallel reading of multiple Parquet files (DuckDB parallelizes automatically)
SELECT 
    file_name,
    COUNT(*) AS row_count,
    SUM(size_bytes) AS total_size
FROM parquet_metadata('s3://bucket/data/*.parquet')
GROUP BY file_name
ORDER BY total_size DESC;
```

### 3. Predicate Pushdown Filtering

```sql
-- Filter during read to reduce data transfer
SELECT * FROM read_parquet('https://storage.example.com/large-dataset.parquet')
WHERE date >= '2025-06-01' AND category = 'electronics';
```

## Architecture Diagram

Here's the overall architecture flow for querying Web APIs with DuckDB:

![DuckDB HTTP + JSON Architecture](/images/posts/duckdb-json-http-api-querying/diagram.png)

## Comparison Summary with Traditional Tools

| Feature | DuckDB HTTP | Python + requests | Excel Power Query | Tableau Data Connectors |
|---------|------------|-------------------|-------------------|------------------------|
| Pure SQL Querying | ✅ | ❌ | Partial | ❌ |
| Nested JSON Parsing | ✅ | ✅ | Limited | ❌ |
| Parallel Reading | ✅ Automatic | Requires multithreading | ❌ | ❌ |
| Large Dataset Processing | ✅ Columnar engine | Memory limited | ❌ | Connector-limited |
| Zero-deployment | ✅ Single file | pip install | ✅ | ✅ |
| Learning Cost | SQL basics | Python programming | Medium | Low |
| Monetization Potential | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ | ⭐⭐ |

## Monetization Guide: How to Make Money with This Skill

After mastering DuckDB's HTTP extension and JSON processing capabilities, you can monetize in several directions:

### 1. Automated Data Reporting Service (Monthly Income $200-$1,000)

Provide daily/weekly automated data reports for small and medium businesses:
- Pull sales data from e-commerce APIs and generate weekly reports automatically
- Scrape brand mentions from social media APIs and produce sentiment analysis reports
- Fetch historical weather data from APIs and provide decision support for agriculture/logistics clients

**Implementation Steps:**
1. Register for DuckDB Cloud or use local DuckDB
2. Write SQL scripts to pull data from target APIs
3. Use `COPY ... TO 'report.csv'` to export results
4. Schedule with cron jobs for automation
5. Deliver reports via email or Slack

### 2. Data Product SaaS (Monthly Income $500-$5,000)

Build data products for specific industries:
- **Real Estate Price Monitor**: Aggregate APIs from multiple property websites for regional price trends
- **Competitor Price Tracker**: Periodically scrape e-commerce product prices and inventory
- **Creator Analytics Dashboard**: Integrate multi-platform data from YouTube/TikTok/Bilibili

**Tech Stack:** DuckDB (data processing) + FastAPI (backend) + Streamlit (frontend)

### 3. Data Consulting Services (Per Project $300-$2,000)

Many companies have data but don't know how to use it. You can offer:
- API data integration solution design
- Migration and optimization of existing data pipelines to DuckDB
- Customized data analysis and reporting development

### 4. Online Courses and Tutorials (Passive Income)

Turn your experience into paid courses:
- "Building a Data Analysis Pipeline from Scratch with DuckDB"
- "Web API Data Scraping and Analysis in Practice"
- "Advanced DuckDB JSON Processing Techniques"

**Key Advantage:** DuckDB's HTTP extension makes data acquisition extremely simple. In your courses, you can focus on "analysis" itself rather than spending extensive time writing scraper code.

---

**Summary:** DuckDB's HTTP extension and JSON functions enable you to complete the entire workflow from data acquisition to analysis using pure SQL. Whether for personal projects or commercial applications, this is a powerful skill combination. Open DuckDB now and try querying an API that interests you!
