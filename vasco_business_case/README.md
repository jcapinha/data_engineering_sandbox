# Survey Data Engineering - Vasco Business Case

## Overview

A daily survey dataset is received as a CSV file. The pipeline ingests it, applies all business rules, and produces clean, analysis-ready tables. The two main questions this solution answers are:

1. Which survey questions have the highest variance in responses?
2. Is there a relationship between years of coding experience and salary?

---

## Project Structure

```
vasco_business_case/
  data/
    raw/                  Source CSV files (input)
    raw_layer/            Raw data as Parquet, unchanged except encoding
    prepared_layer/       Cleaned and transformed data
    staging_layer/        Final tables for consumption
  notebooks/
    etl_pipeline.ipynb    The full ETL pipeline
  schema/
    create_tables.sql     Table DDL for the staging layer
  docs/
    architecture.drawio.png   Architecture diagram
```

---

## Architecture Diagram

Architecture Diagram

---

## Running the Pipeline

1. Place `RawData.csv` and `Columns.csv` in `data/raw/`.
2. Open `notebooks/etl_pipeline.ipynb`.
3. Check the first cell (parameters) and update the paths if the files are in a different location.
4. Run all cells in order.

Output Parquet files are written to `data/raw_layer/`, `data/prepared_layer/`, and `data/staging_layer/`. Any files from a previous run are cleaned up automatically at the start, so you can run the notebook as many times as you want, without creating "trash". 

Small note: Because the files only get deleted at the start of the notebook, they are only erased when running that cell. If you run everything just once, you'll keep files in the folders. It's not a problem at all, it's just for awarness.

To run ad-hoc SQL queries against the output, the last cell in the notebook uses DuckDB to query the Parquet files directly with no database setup required.

---

## Why Parquet?

The source files are CSV. Every downstream layer is written as Parquet instead because:

- **Encoding is fixed automatically.** Parquet stores everything as UTF-8 internally, so whatever encoding the source CSV has, all layers downstream read clean characters.
- **Great compression and query performance.** Parquet is columnar, meaning queries that touch only a few columns skip the rest entirely. This is especially relevant for variance calculations across 100+ columns.
- **Schema is embedded.** Column types are stored in the file, which reduces the risk of type mismatches when loading into a database or querying with a tool like DuckDB.

---

## Pipeline Layers

The pipeline follows three layers, each written as a separate Parquet file, in different directories.

### Raw Layer

The pipeline reads the CSV using automatic encoding detection (`chardet`). A 200KB sample of the file is enough — chardet's confidence stabilises within the first few KB, so reading the full file would not change the result and would be slower on larger files. This enables (`pandas`) to read the CSV. After converting everything to parquet, it will no longer be an issue, as I explained before.
The data lands in the Raw Layer as-is, with two metadata columns added to every row: `_ingestion_date` and `_source_file`. These allow any record to be traced back to the exact file and run that produced it.

### Prepared Layer

The business rules are applied to a copy of the raw data, so the Raw Layer is never modified. This is important to insure the Raw Layer is kept as a "source of truth" of what data was received in the CSVs.


| Rule                           | What it does                                                                                                                                                                                                                                                                                                                              |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| BR1 - Unique respondents       | Deduplicates on `Respondent`, keeping the first occurrence. A warning is logged if duplicates are found, as this points to a setup issue in the survey tool.                                                                                                                                                                              |
| BR2 - Blank Student            | Fills blank values with `"No"`. According to the business case, ablank means the respondent is not a student.                                                                                                                                                                                                                          |
| BR3 - Blank Employment         | Fills blank values with `"Employed full-time"`. Same as above.                                                                                                                                                                                                                                                                  |
| BR4 - More than 3 empty fields | Does not drop rows. Instead, adds three columns: `empty_field_count`, `empty_fields` (list of which fields are null), and `more_than_three_empty` (boolean flag). Dropping rows would remove around 96% of the dataset, so I added the flag let the business decide what to do.                                          |
| BR5 - Yearly salary            | Calculates a `salary_yearly` column from `Salary` and `SalaryType`. Weekly values are multiplied by 52, Monthly by 12, and Yearly is kept as-is. Rows with a salary value but no `SalaryType` are set to null, since without knowing the frequency, I cannot know if the value makes sense and it could skew the analysis of the client. The original `Salary` and `SalaryType` columns are preserved. |


### Staging Layer

The Staging Layer holds a trimmed version of the prepared data with only the columns needed for the two analyses, plus key demographic attributes so results can be broken down by country, dev type, employment, etc. All column names follow `snake_case` for SQL compatibility.

`fact_survey` is the **primary deliverable**. The full prepared dataset remains available in the Prepared Layer if more columns are needed later.

---

## Analyses

### Variance by Question (`fact_variance`)

The pipeline calculates variance across all numeric survey columns. Three columns are excluded from the ranking: `Respondent` (a row ID), `ConvertedSalary`, and `salary_yearly`. Their variance is driven by monetary scale and currency mix rather than by how respondents answered a question, so including them would make the ranking meaningless.

`fact_variance` is a pre-calculated snapshot of the full dataset, giving the business an immediate answer without writing any queries. For any filtered analysis (e.g. variance only for full-time employees), `fact_survey` is the right starting point.

### Salary vs. Years Coding (correlation)

`YearsCoding` is stored as a text range (e.g. `"6-8 years"`). The pipeline maps each range to its midpoint (e.g. `7`) to make the correlation calculation possible. It then calculates the Pearson correlation between `years_coding_numeric` and `ConvertedSalary`. USD-converted salary is used rather than `salary_yearly` to ensure a fair comparison across countries.

---

## Table Schema

See `[schema/create_tables.sql](schema/create_tables.sql)` for the full DDL.

Two tables are defined:

- `**staging.fact_survey`** - one row per respondent, all columns needed for analysis.
- `**staging.fact_variance**` - one row per survey question, with its variance across all respondents.

`VARCHAR(100)` is the default for all text columns.

---

## Cloud Implementation (Azure / Microsoft Fabric)

The pipeline runs locally using Python and pandas. The same logic translates to Azure without structural changes. The only thing changing would be the paths and execution environment.

### Storage

Each layer can be stored in **Azure Data Lake Storage** as Parquet files, partitioned by ingestion date. The three-layer structure (Raw, Prepared, Staging) maps directly to separate containers or folders in the same storage account. The partitioning by ingestion data would make it even better for the client to analyse the data, by ensuring only the data in the partitions relevant to the client queries is scanned and loaded.

### Processing

The notebook logic maps 1:1 to a **Microsoft Fabric Notebook**. It is basically Microsoft's version of Jupyter Notebook in their "ecosystem". Or if I wanted to use Spark to process the data (no need here since it was a small amount of data), I could even use a **Azure Databricks** notebook using PySpark. It would just be small changes in some functions use to open the CSV files and creating dataframes The code logic, flow and business rules itself wouldn't change at all. I am someone who doesn't like to use overblown solutions to simple problems, so for data sizes like this, I would probably stay with pandas and dataframes instead of PySpark. I would only change if the data amount was expected to scale.

### Orchestration

A **Fabric Data Factory pipeline** could trigger the notebook daily on a schedule. The input file paths could be passed as parameters to the notebook, which is why I already defined them in a separate parameters cell at the top of the notebook. 
Other possibility would be triggered when a new file would be uploaded to a specific location on Azure Data Lake Storage, but the specific code would have to be developed for this, and some sort of notification system would needed to be set up for orchastrating all of this. 

Like I mentioned before, I prefer to keep simple solutions for simple problems, and not spend too much time in focusing in overengineering things. If the problem gets solved by a simple solution, I prefer to implement that, and spend the spare time talking to the users to see if there is any other needs or edge cases that need to be covered by the code.

### Serving

To make the output queryable in Azure, I would probably use **Fabric Data Warehouse**. The DDL in `create_tables.sql` can be executed directly to create the tables, and a `COPY INTO` command would load the Parquet files into them. This would create a "normal" SQL interface in Fabric. 
Then, it would be a matter of building any reporting solutions of Fabric connected to these tables and the reports would get the data necessary.