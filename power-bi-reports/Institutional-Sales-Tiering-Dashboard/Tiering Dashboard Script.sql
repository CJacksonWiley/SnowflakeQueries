/*
=============================================================================
Script: Institutional Sales Tiering Dashboard
=============================================================================
Purpose: Combines institutional classification with revenue analysis to 
         create customer tiers for sales prioritization
         
Tables Used:
  - customer_dim
  - sales_fact  
  - institution tables
  
Output: Powers the Sales Tiering Power BI dashboard used by account managers
        across the organization
        
Created: November 2024
Author: Chris Jackson
Last Modified: 2024-11-20
=============================================================================
*/

WITH base_data_raw AS (
    -- First, get all the data WITHOUT the OUTPUT_TIER calculation
    SELECT 
        RINGGOLD_ID__C, 
        AC.ID, 
        AC.NAME, 
        AC.INDUSTRY_CLASSIFICATION__C,  -- ADDED: New column
        AC.SALES_REGION__C,  -- ADDED: New column
        C.PRID, 
        C.PRID_NAME, 
        AC.LS_SEGMENT__C, 
        LS_TERRITORY__C, 
        INSTITUTIONAL_SALES_TIER__C,
        AM.NAME AS LIBRARY_ACCOUNT_MANAGER, 
        SAM.NAME AS LIBRARY_STRATEGIC_ACCOUNT_MANAGER,
        TT.TIER, 
        TT.DESCRIPTION, 
        SPLIT_PART(I.TYPE,'/',1) as MAIN_TYPE, 
        I.TYPE,
        SUM(Op.AMOUNT_AT_CLOSEDATE_FX_RATE_IN_USD__C) AS AMOUNT_CLOSE, 
        MAX(TB.LEAD_AUTHOR_TOTAL_ART) AS LEAD_AUTHOR_TOTAL_ART,  -- FIXED: Changed to MAX
        
        -- RG_TIER calculation
        CASE 
            WHEN TT.TIER IN ('A4','A5','A6','A9','C5','G5','G9','H5','H9','M9','N5','N9','P9') THEN 1
            WHEN TT.TIER IN ('A3','C3','C4','G3','G4','H3','H4','M3','M4','N3','N4','P3','P4') THEN 2
            WHEN TT.TIER IN ('A1','A2','C1','C2','D','G1','G2','H1','H2','M1','M2','N1','N2','P1','P2') THEN 3
            ELSE NULL 
        END AS RG_TIER
        
    FROM (SELECT * FROM PROD_ODS.SFDC.T_S_SFDC_ACCOUNT WHERE ISDELETED = false) AS AC
    
    LEFT JOIN PROD_EDW.DS.LKP_CUSTOMER C ON AC.ID = C.SFDC_ID
    LEFT JOIN PROD_ODS.RINGGOLD.RINGGOLD_INSTITUTIONS_MDM AS I ON C.PRID = I.RINGGOLD_ID
    
    LEFT JOIN (
        SELECT T.RINGGOLD_ID, T.TIER, TX.DESCRIPTION 
        FROM (
            SELECT RINGGOLD_ID, VALUE AS TIER 
            FROM PROD_ODS.RINGGOLD.RINGGOLD_TIERS_MDM 
            WHERE TIER_TYPE = 'RGT'
        ) AS T 
        LEFT JOIN (
            SELECT NAME, DESCRIPTION 
            FROM PROD_ODS.RINGGOLD.RINGGOLD_TAXONOMY_MDM 
            WHERE VOCABULARY = 'rg_tiers'
        ) AS TX ON T.TIER = TX.NAME
    ) AS TT ON TT.RINGGOLD_ID = C.PRID
    
    LEFT JOIN (
        SELECT ACCOUNTID, SUM(AMOUNT_AT_CLOSEDATE_FX_RATE_IN_USD__C) AS AMOUNT_AT_CLOSEDATE_FX_RATE_IN_USD__C 
        FROM PROD_ODS.SFDC.T_S_SFDC_OPPORTUNITY 
        WHERE FISCALYEAR = YEAR(CURRENT_DATE)-1 
        AND STAGENAME IN ('Invoiced') 
        AND OPPORTUNITY_RECORDTYPE__C IN ('Institutional Sales') 
        GROUP BY ACCOUNTID
    ) AS OP ON OP.ACCOUNTID = AC.ID
    
    LEFT JOIN (
        SELECT *
        FROM (
            SELECT DISTINCT 
                LAM.NAME AS NAME,
                atm.ACCOUNTID,
                atm.TEAMMEMBERROLE,
                atm.USERID,
                atm.TITLE,
                atm.LASTMODIFIEDDATE,
                ROW_NUMBER() OVER (PARTITION BY atm.ACCOUNTID ORDER BY atm.LASTMODIFIEDDATE DESC) AS ROW_NUMBER
            FROM PROD_ODS.SFDC.T_S_SFDC_ACCOUNT_TEAM_MEMBER atm
            LEFT JOIN PROD_ODS.SFDC.T_S_SFDC_USER lam ON lam.id = atm.USERID
            WHERE atm.TEAMMEMBERROLE in ('IS Account Manager','Library Account Manager')
            AND atm.ISDELETED = FALSE
        ) sub 
        WHERE ROW_NUMBER = 1
    ) AS AM ON AM.ACCOUNTID = AC.ID
    
    LEFT JOIN (
        SELECT *
        FROM (
            SELECT DISTINCT 
                LAM.NAME AS NAME,
                atm.ACCOUNTID,
                atm.TEAMMEMBERROLE,
                atm.USERID,
                atm.TITLE,
                atm.LASTMODIFIEDDATE,
                ROW_NUMBER() OVER (PARTITION BY atm.ACCOUNTID ORDER BY atm.LASTMODIFIEDDATE DESC) AS ROW_NUMBER
            FROM PROD_ODS.SFDC.T_S_SFDC_ACCOUNT_TEAM_MEMBER atm
            LEFT JOIN PROD_ODS.SFDC.T_S_SFDC_USER lam ON lam.id = atm.USERID
            WHERE atm.TEAMMEMBERROLE in ('IS Strategic Account Manager','Library Strategic Account Manager')
            AND atm.ISDELETED = FALSE
        ) sub 
        WHERE ROW_NUMBER = 1
    ) AS SAM ON SAM.ACCOUNTID = AC.ID  -- FIXED: Changed from AM.ACCOUNTID to SAM.ACCOUNTID
    
    LEFT JOIN (
        SELECT SFDC_ID, 
               SUM(LEAD_AUTHOR_SUB_ART) AS LEAD_AUTHOR_SUB_ART, 
               SUM(LEAD_AUTHOR_OA_ART) AS LEAD_AUTHOR_OA_ART, 
               SUM(LEAD_AUTHOR_OO_ART) AS LEAD_AUTHOR_OO_ART, 
               (SUM(LEAD_AUTHOR_SUB_ART) + SUM(LEAD_AUTHOR_OA_ART) + SUM(LEAD_AUTHOR_OO_ART)) AS LEAD_AUTHOR_TOTAL_ART
        FROM (
            SELECT B.PRID, C.SFDC_ID, B.DATASALON_CODE,
                COALESCE(CASE WHEN OPEN_ACCESS_TYPE = 'Controlled' THEN SUM(REPRINT_ARTICLE_CNT) END,0) AS LEAD_AUTHOR_SUB_ART,
                COALESCE(CASE WHEN (OPEN_ACCESS_TYPE = 'Title Open Access' OR OPEN_ACCESS_TYPE = 'Open Access') THEN SUM(REPRINT_ARTICLE_CNT) END,0) AS LEAD_AUTHOR_OA_ART,
                COALESCE(CASE WHEN (OPEN_ACCESS_TYPE = 'Hybrid Open Access' OR OPEN_ACCESS_TYPE = 'Online Open')THEN SUM(REPRINT_ARTICLE_CNT) END,0) AS LEAD_AUTHOR_OO_ART
            FROM PROD_EDW.DS.STG_DATASALON_EXTRACT_B1M B
            LEFT JOIN PROD_EDW.DS.LKP_CUSTOMER C ON B.PRID = C.PRID
            WHERE PUB_YEAR = YEAR(CURRENT_DATE)-1
            GROUP BY B.PRID, C.SFDC_ID, B.DATASALON_CODE, OPEN_ACCESS_TYPE
        ) AS B1
        GROUP BY SFDC_ID
    ) TB ON TB.SFDC_ID = AC.ID
    
    WHERE AC.LS_SEGMENT__C IS NOT NULL
    
    GROUP BY RINGGOLD_ID__C, AC.ID, AC.NAME, AC.INDUSTRY_CLASSIFICATION__C, AC.SALES_REGION__C,  -- ADDED: To GROUP BY
             C.PRID, C.PRID_NAME, AC.LS_SEGMENT__C, LS_TERRITORY__C, 
             INSTITUTIONAL_SALES_TIER__C, AM.NAME, SAM.NAME,
             TT.TIER, TT.DESCRIPTION, MAIN_TYPE, I.TYPE
             -- REMOVED TB.LEAD_AUTHOR_TOTAL_ART from GROUP BY
),
segment_averages AS (
    -- Calculate the average LEAD_AUTHOR_TOTAL_ART for each segment
    SELECT 
        LS_SEGMENT__C,
        AVG(LEAD_AUTHOR_TOTAL_ART) AS AVG_LEAD_AUTHOR_TOTAL_ART
    FROM base_data_raw
    WHERE LEAD_AUTHOR_TOTAL_ART IS NOT NULL AND LEAD_AUTHOR_TOTAL_ART > 0
    GROUP BY LS_SEGMENT__C
),
base_data AS (
    -- Join back to add the averages and calculate OUTPUT_TIER with dynamic thresholds
    SELECT 
        b.*,
        sa.AVG_LEAD_AUTHOR_TOTAL_ART AS SEGMENT_AVG_LEAD_AUTHOR,
        
        -- OUTPUT_TIER calculation using dynamic averages
        CASE 
            WHEN b.LEAD_AUTHOR_TOTAL_ART = 0 THEN 3
            WHEN b.LEAD_AUTHOR_TOTAL_ART IS NULL THEN 3
            WHEN b.LEAD_AUTHOR_TOTAL_ART >= sa.AVG_LEAD_AUTHOR_TOTAL_ART THEN 1
            ELSE 2
        END AS OUTPUT_TIER
        
    FROM base_data_raw b
    LEFT JOIN segment_averages sa ON b.LS_SEGMENT__C = sa.LS_SEGMENT__C
)
SELECT 
    *,
    -- SPEND_TIER calculation
    CASE 
        WHEN LS_SEGMENT__C = 'Strategic' AND AMOUNT_CLOSE > 500000 THEN 1
        WHEN LS_SEGMENT__C = 'Strategic' AND AMOUNT_CLOSE > 250000 THEN 2
        WHEN LS_SEGMENT__C = 'Strategic' AND AMOUNT_CLOSE IS NOT NULL THEN 3
        WHEN LS_SEGMENT__C = 'Core' AND AMOUNT_CLOSE > 350000 THEN 1
        WHEN LS_SEGMENT__C = 'Core' AND AMOUNT_CLOSE > 100000 THEN 2
        WHEN LS_SEGMENT__C = 'Core' AND AMOUNT_CLOSE IS NOT NULL THEN 3
        WHEN LS_SEGMENT__C = 'Specialty' AND AMOUNT_CLOSE > 500000 THEN 1
        WHEN LS_SEGMENT__C = 'Specialty' AND AMOUNT_CLOSE > 150000 THEN 2
        WHEN LS_SEGMENT__C = 'Specialty' AND AMOUNT_CLOSE IS NOT NULL THEN 3
        WHEN AMOUNT_CLOSE > 350000 THEN 1
        WHEN AMOUNT_CLOSE > 100000 THEN 2
        ELSE 3 
    END AS SPEND_TIER,
    
    -- DERIVED_SALES_TIER with weighted calculation for Specialty
    CASE 
        -- Special handling for Specialty segment - double weight on SPEND_TIER
        WHEN LS_SEGMENT__C = 'Specialty' THEN
            CASE 
                WHEN COALESCE(RG_TIER, 3) + OUTPUT_TIER + 
                     (2 * CASE  -- Double weight for SPEND_TIER
                        WHEN AMOUNT_CLOSE > 500000 THEN 1
                        WHEN AMOUNT_CLOSE > 150000 THEN 2
                        WHEN AMOUNT_CLOSE IS NOT NULL THEN 3
                        ELSE 3 
                     END) <= 6 THEN 1
                WHEN COALESCE(RG_TIER, 3) + OUTPUT_TIER + 
                     (2 * CASE  -- Double weight for SPEND_TIER
                        WHEN AMOUNT_CLOSE > 500000 THEN 1
                        WHEN AMOUNT_CLOSE > 150000 THEN 2
                        WHEN AMOUNT_CLOSE IS NOT NULL THEN 3
                        ELSE 3 
                     END) <= 9 THEN 2
                ELSE 3
            END
        -- Standard calculation for Strategic and Core
        ELSE
            CASE 
                WHEN COALESCE(RG_TIER, 3) + OUTPUT_TIER + 
                     CASE  -- Standard weight for SPEND_TIER
                        WHEN LS_SEGMENT__C = 'Strategic' AND AMOUNT_CLOSE > 500000 THEN 1
                        WHEN LS_SEGMENT__C = 'Strategic' AND AMOUNT_CLOSE > 250000 THEN 2
                        WHEN LS_SEGMENT__C = 'Strategic' AND AMOUNT_CLOSE IS NOT NULL THEN 3
                        WHEN LS_SEGMENT__C = 'Core' AND AMOUNT_CLOSE > 350000 THEN 1
                        WHEN LS_SEGMENT__C = 'Core' AND AMOUNT_CLOSE > 100000 THEN 2
                        WHEN LS_SEGMENT__C = 'Core' AND AMOUNT_CLOSE IS NOT NULL THEN 3
                        WHEN AMOUNT_CLOSE > 350000 THEN 1
                        WHEN AMOUNT_CLOSE > 100000 THEN 2
                        ELSE 3 
                     END < 6 THEN 1
                WHEN COALESCE(RG_TIER, 3) + OUTPUT_TIER + 
                     CASE  -- Standard weight for SPEND_TIER
                        WHEN LS_SEGMENT__C = 'Strategic' AND AMOUNT_CLOSE > 500000 THEN 1
                        WHEN LS_SEGMENT__C = 'Strategic' AND AMOUNT_CLOSE > 250000 THEN 2
                        WHEN LS_SEGMENT__C = 'Strategic' AND AMOUNT_CLOSE IS NOT NULL THEN 3
                        WHEN LS_SEGMENT__C = 'Core' AND AMOUNT_CLOSE > 350000 THEN 1
                        WHEN LS_SEGMENT__C = 'Core' AND AMOUNT_CLOSE > 100000 THEN 2
                        WHEN LS_SEGMENT__C = 'Core' AND AMOUNT_CLOSE IS NOT NULL THEN 3
                        WHEN AMOUNT_CLOSE > 350000 THEN 1
                        WHEN AMOUNT_CLOSE > 100000 THEN 2
                        ELSE 3 
                     END < 8 THEN 2
                ELSE 3
            END
    END AS DERIVED_SALES_TIER
FROM base_data