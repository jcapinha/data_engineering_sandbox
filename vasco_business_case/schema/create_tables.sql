-- =============================================================================
-- Staging Layer -- Table Schemas
-- Survey ETL Pipeline
-- =============================================================================
-- When to use:
--   This script applies to the Fabric Data Warehouse path. In that setup, tables
--   are created explicitly and data is loaded into them via a pipeline (e.g. a
--   COPY INTO statement or a Fabric Data Factory pipeline writing to the warehouse).
--   Run CREATE SCHEMA staging; first, then execute this script to create the tables.
-- =============================================================================
-- These tables represent the Staging (consumption) layer of the pipeline.
-- They are written as Parquet locally and would be registered as external or
-- managed tables in Azure Synapse Analytics or Microsoft Fabric SQL endpoint.
--
-- fact_survey is the main table for this business case. It contains the processed and cleaned data
-- with all business rules applied and gives the business everything they need to run the two requested analyses themselves, 
-- with full flexibility to filter by any field they choose.
--
-- fact_variance is an extra snapshot, with the intended analysis already calculated. This allows the business to have an immediate answer for the whole ingestion 
-- without writing any queries. For any other filtering or analysis, use 'fact_survey' should be used.
-- Note: Non-question columns (salary_yearly, ConvertedSalary, Respondent) are excluded. Check the notebook for more details.
-- =============================================================================

CREATE TABLE staging.fact_survey (

    respondent_id           INT             NOT NULL,   -- Unique respondent identifier (source: Respondent)
    country                 VARCHAR(100)    NULL,
    gender                  VARCHAR(100)    NULL,
    age                     VARCHAR(100)    NULL,       -- Stored as a range string (e.g. "25-34 years old")
    student                 VARCHAR(100)    NOT NULL,   -- 'Yes' or 'No'; NULL defaulted to 'No' (BR2)
    employment              VARCHAR(100)    NOT NULL,   -- NULL defaulted to 'Employed full-time' (BR3)
    formal_education        VARCHAR(100)    NULL,
    undergrad_major         VARCHAR(100)    NULL,
    company_size            VARCHAR(100)    NULL,
    dev_type                VARCHAR(500)    NULL,       -- Semicolon-delimited multi-select; kept higher to avoid truncating long combined values
    years_coding            VARCHAR(100)    NULL,       -- Original range string (e.g. "6-8 years")
    years_coding_prof       VARCHAR(100)    NULL,       -- Professional experience range string
    job_satisfaction        VARCHAR(100)    NULL,
    career_satisfaction     VARCHAR(100)    NULL,
    salary_original         VARCHAR(100)    NULL,       -- Raw value from source, preserved for analysis/debugging
    salary_type             VARCHAR(100)    NULL,       -- 'Weekly', 'Monthly', or 'Yearly'
    salary_yearly           FLOAT           NULL,       -- Calculated to yearly in local currency (BR5)
    converted_salary_usd    FLOAT           NULL,       -- Pre-converted to USD by the survey provider (2018 rates, annualised)
    currency                VARCHAR(100)    NULL,
    currency_symbol         VARCHAR(100)    NULL,
    empty_field_count       INT             NOT NULL,   -- Number of NULL survey fields per row
    more_than_three_empty   BIT             NOT NULL,   -- 1 if empty_field_count > 3 (BR4 flag)
    _ingestion_date         DATE            NOT NULL,   -- Date the record was loaded by the pipeline
    _source_file            VARCHAR(100)    NOT NULL    -- Name of the source CSV file

);

CREATE TABLE staging.fact_variance (

    question                VARCHAR(100)    NOT NULL,   -- Survey question / column name
    variance                FLOAT           NOT NULL    -- Variance of responses across all respondents

);
