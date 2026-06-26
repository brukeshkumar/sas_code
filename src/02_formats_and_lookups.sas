/*=============================================================================
  File    : config/02_formats_and_lookups.sas
  Purpose : All proc format definitions used across the pipeline.
            Stored in WORK (fmtsearch picks them up automatically).
=============================================================================*/

proc format library=WORK;

  /* ── FICO Score Banding ── */
  value FICO_BAND
    300  - 579  = '1_SubPrime (<580)'
    580  - 619  = '2_NearPrime (580-619)'
    620  - 659  = '3_FairCredit (620-659)'
    660  - 719  = '4_GoodCredit (660-719)'
    720  - 759  = '5_VeryGood (720-759)'
    760  - 850  = '6_Excellent (760-850)'
    other       = '0_Unknown'
  ;

  /* ── Current LTV Banding ── */
  value LTV_BAND
    low  -<  60 = '1_<=60%'
    60   -<  75 = '2_60-75%'
    75   -<  80 = '3_75-80%'
    80   -<  90 = '4_80-90%'
    90   -<  95 = '5_90-95%'
    95   -<  97 = '6_95-97%'
    97   - high = '7_>97% High Risk'
    other       = '0_Unknown'
  ;

  /* ── Days Past Due Buckets ── */
  value DPD_BUCKET
    0           = '00_Current'
    1  -  29   = '01_DPD01-29'
    30 -  59   = '02_DPD30-59'
    60 -  89   = '03_DPD60-89'
    90 - 119   = '04_DPD90-119'
    120- 179   = '05_DPD120-179'
    180- high  = '06_DPD180+'
    other      = '99_Unknown'
  ;

  /* ── DTI Banding ── */
  value DTI_BAND
    low -< 28  = '1_<=28 Front-End'
    28  -< 36  = '2_28-36 Acceptable'
    36  -< 43  = '3_36-43 Elevated'
    43  -< 50  = '4_43-50 High'
    50  - high = '5_>50 Very High'
    other      = '0_Unknown'
  ;

  /* ── Loan Age Banding ── */
  value AGE_BAND
    low -<  12 = '01_0-12mo'
    12  -<  24 = '02_13-24mo'
    24  -<  36 = '03_25-36mo'
    36  -<  60 = '04_37-60mo'
    60  -< 120 = '05_61-120mo'
    120 - high = '06_120mo+'
    other      = '00_Unknown'
  ;

  /* ── Loan Purpose ── */
  value $LOAN_PURPOSE
    'P'   = 'Purchase'
    'C'   = 'Cash-Out Refi'
    'N'   = 'Rate-Term Refi'
    'U'   = 'Unknown'
    other = 'Other'
  ;

  /* ── Occupancy Type ── */
  value $OCC_TYPE
    'P'   = 'Primary Residence'
    'S'   = 'Second Home'
    'I'   = 'Investment Property'
    other = 'Unknown'
  ;

  /* ── Property Type ── */
  value $PROP_TYPE
    'SF'  = 'Single Family'
    'PU'  = 'PUD'
    'CO'  = 'Condo'
    'MH'  = 'Manufactured Housing'
    '2F'  = '2-4 Unit'
    other = 'Other'
  ;

  /* ── Origination Channel ── */
  value $CHANNEL
    'R'   = 'Retail'
    'B'   = 'Broker'
    'C'   = 'Correspondent'
    'T'   = 'TPO'
    other = 'Unknown'
  ;

  /* ── Zero Balance Code (Payoff reason) ── */
  value $ZBC
    '01'  = 'Prepaid/Matured'
    '02'  = 'Third Party Sale'
    '03'  = 'Short Sale'
    '06'  = 'Repurchase'
    '09'  = 'REO Disposition'
    '15'  = 'Reperforming Loan Sale'
    '16'  = 'Reperforming Loan Sale'
    other = 'Other/Active'
  ;

  /* ── Modification Flag ── */
  value $MOD_FLAG
    'Y'   = 'Modified'
    'N'   = 'Not Modified'
    other = 'Unknown'
  ;

  /* ── State → Geographic Region mapping ── */
  value $STATE_REGION
    'CA','WA','OR','NV','AZ','HI','AK','ID','UT','MT','WY','CO','NM'
                                    = 'West'
    'TX','OK','KS','NE','SD','ND','MN','IA','MO','AR','LA'
                                    = 'South Central'
    'FL','GA','SC','NC','VA','TN','AL','MS','KY','WV'
                                    = 'Southeast'
    'NY','NJ','CT','MA','RI','VT','NH','ME','PA','MD','DE','DC'
                                    = 'Northeast'
    'OH','MI','IN','IL','WI'        = 'Midwest'
    other                           = 'Other'
  ;

  /* ── Judicial vs Non-Judicial Foreclosure State ── */
  value $FC_TYPE
    'NY','NJ','FL','IL','CT','HI','IN','KS','KY','LA','ME',
    'ND','OH','OK','PA','SC','VT','WI'
                                    = 'Judicial'
    other                           = 'Non-Judicial'
  ;

  /* ── IFRS9 Stage Label ── */
  value $IFRS9
    'S1'  = 'Stage 1 - Performing'
    'S2'  = 'Stage 2 - Underperforming'
    'S3'  = 'Stage 3 - Credit Impaired'
    other = 'Unknown'
  ;

run;
