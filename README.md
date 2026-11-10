# instacart-json-snowflake-etl
Working with Semi structured data on Snowflake

# Instacart JSON ETL Pipeline using Snowflake

## Project Overview

This project demonstrates how to transform nested JSON event data into structured, analytics-ready CSV tables using Snowflake SQL.

The input consists of application event data containing nested JSON payloads.

## Technologies Used

- Snowflake SQL
- Semi-structured data processing
- VARIANT data type
- PARSE_JSON()
- LATERAL FLATTEN()
- COPY INTO

## Architecture

JSON File → Snowflake Internal Stage → RAW_EVENTS → SQL Transformations → Analytics Tables → CSV Exports

## Output Tables

| Table | Records |
|---|---:|
| CuratedOfferOptions | 40 |
| DynamicPriceOption | 56 |
| DynamicPriceRange | 25 |
| Total | 121 |

## Key Concepts

- Loading JSON files into Snowflake.
- Parsing nested JSON strings.
- Flattening nested arrays using LATERAL FLATTEN.
- Extracting attributes from JSON objects.
- Converting semi-structured data into relational tables.
- Exporting tables into CSV files using COPY INTO.

## Project Structure

- `sql/` – Snowflake SQL scripts.
- `output/` – Three transformed CSV files.
- `README.md` – Project documentation.

## Result

Successfully transformed 37 source events into 121 analytics-ready records across three output tables.
