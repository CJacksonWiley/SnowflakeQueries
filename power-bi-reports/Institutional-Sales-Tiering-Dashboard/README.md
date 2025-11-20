# Institutional Sales Tiering Dashboard

## Overview
This SQL script powers the Institutional Sales Tiering Dashboard in Power BI, used by account managers and the sales team across Wiley to prioritize customer accounts based on institutional classification, revenue, and research output.

## Purpose
Combines multiple data sources to create a composite tiering system that helps the sales team identify:
- High-value institutional customers
- Research-active institutions with growth potential
- Accounts requiring strategic attention vs. standard management

## Tiering Methodology

The script calculates **four distinct tier types** that combine into a final `DERIVED_SALES_TIER`:

### 1. RG_TIER (Ringgold Institution Tier)
Based on Ringgold's institutional classification system:
- **Tier 1**: Premium institutions (A4, A5, A6, A9, C5, G5, etc.)
- **Tier 2**: Mid-level institutions (A3, C3, C4, G3, etc.)
- **Tier 3**: Standard institutions (A1, A2, C1, C2, etc.)

### 2. OUTPUT_TIER (Research Output)
Measures research publication activity using lead author article counts:
- **Tier 1**: Above segment average for lead author publications
- **Tier 2**: Below segment average but has publications
- **Tier 3**: No publication activity (0 or NULL)

Calculated dynamically by LS_SEGMENT for accurate comparison within peer groups.

### 3. SPEND_TIER (Revenue)
Based on prior fiscal year invoiced revenue, with thresholds varying by segment:

**Strategic Segment:**
- Tier 1: >$500K
- Tier 2: >$250K
- Tier 3: <$250K or NULL

**Core Segment:**
- Tier 1: >$350K
- Tier 2: >$100K
- Tier 3: <$100K or NULL

**Specialty Segment:**
- Tier 1: >$500K
- Tier 2: >$150K
- Tier 3: <$150K or NULL

### 4. DERIVED_SALES_TIER (Final Combined Tier)
Weighted combination of RG_TIER + OUTPUT_TIER + SPEND_TIER:

**Standard calculation (Strategic & Core):**
- Sum < 6 → Tier 1
- Sum < 8 → Tier 2
- Sum ≥ 8 → Tier 3

**Specialty segment:** SPEND_TIER is double-weighted to emphasize revenue importance for specialty accounts.

## Data Sources

### Primary Tables
- **PROD_ODS.SFDC.T_S_SFDC_ACCOUNT** - Salesforce account data
- **PROD_EDW.DS.LKP_CUSTOMER** - Customer dimension with PRID mapping
- **PROD_ODS.RINGGOLD.RINGGOLD_INSTITUTIONS_MDM** - Ringgold institution master data
- **PROD_ODS.RINGGOLD.RINGGOLD_TIERS_MDM** - Ringgold tier classifications
- **PROD_ODS.SFDC.T_S_SFDC_OPPORTUNITY** - Salesforce opportunity/revenue data
- **PROD_ODS.SFDC.T_S_SFDC_ACCOUNT_TEAM_MEMBER** - Account manager assignments
- **PROD_EDW.DS.STG_DATASALON_EXTRACT_B1M** - DataSalon publication data

### Time Period
- **Revenue data**: Prior fiscal year (FISCALYEAR = YEAR(CURRENT_DATE)-1)
- **Publication data**: Prior calendar year (PUB_YEAR = YEAR(CURRENT_DATE)-1)

## Key Fields in Output

| Field | Description |
|-------|-------------|
| RINGGOLD_ID__C | Ringgold institution identifier |
| NAME | Account name from Salesforce |
| LS_SEGMENT__C | Library segment (Strategic/Core/Specialty) |
| INSTITUTIONAL_SALES_TIER__C | Salesforce native tier field |
| LIBRARY_ACCOUNT_MANAGER | Assigned account manager |
| LIBRARY_STRATEGIC_ACCOUNT_MANAGER | Assigned strategic account manager |
| AMOUNT_CLOSE | Prior year invoiced revenue (USD) |
| LEAD_AUTHOR_TOTAL_ART | Total lead author articles published |
| RG_TIER | Ringgold-based tier (1-3) |
| OUTPUT_TIER | Publication-based tier (1-3) |
| SPEND_TIER | Revenue-based tier (1-3) |
| DERIVED_SALES_TIER | Final composite tier (1-3) |

## Usage

### In Snowflake
Run the full script to generate the complete tiering dataset. The query typically takes 2-5 minutes to execute depending on data volume.

### In Power BI
This query feeds the "Institutional Sales Tiering Dashboard" and should be scheduled for weekly refresh to keep account manager assignments and recent revenue current.

### Filtering
The base query filters to accounts where `LS_SEGMENT__C IS NOT NULL`, focusing on library segment accounts only.

## Maintenance Notes

### When to Update
- **Annually**: Review tier thresholds if business priorities shift
- **Quarterly**: Verify account manager assignments are current
- **As needed**: Adjust segment averages calculation if segments are redefined

### Known Considerations
- Account team members are deduplicated using the most recent `LASTMODIFIEDDATE`
- Publications are aggregated across all article types (subscription, OA, hybrid)
- NULL revenue is treated as Tier 3 (lowest priority)
- RG_TIER defaults to 3 if Ringgold tier is missing

## Related Resources
- Power BI Dashboard: [Link to dashboard]
- Ringgold Documentation: [Internal wiki/SharePoint]
- Segment Definitions: [Internal documentation]

## History
- **Created**: November 2024
- **Author**: Chris Jackson, EDA Research and Learning
- **Last Modified**: 2024-11-20

## Questions or Issues?
Contact the EDA Research and Learning team or submit feedback through the Power BI dashboard.