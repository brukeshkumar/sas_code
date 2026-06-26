/*=============================================================================
  FREDDIE MAC - MORTGAGE PORTFOLIO ANALYTICS SYSTEM
  Program  : mortgage_portfolio_analytics.sas
  Purpose  : Single-Family Loan Performance, Credit Risk Scoring,
             Delinquency Reporting, and Loss Estimation
  Team     : Finance & Credit Analytics
  Updated  : 2024-Q1
  
  MODULES:
    1. Global Macro Parameters & Library Setup
    2. Reference Data Loading & Lookup Tables
    3. Loan-Level Data Staging & Cleansing
    4. Credit Score Banding & LTV Mapping
    5. Delinquency Bucket Classification
    6. SQL-Based Portfolio Aggregation
    7. Loss Given Default (LGD) Estimation
    8. Probability of Default (PD) Scoring
    9. Expected Credit Loss (ECL) Computation
   10. Cohort-Level Roll Rate Analysis
   11. State-Level Heatmap Summary
   12. Final Reporting & Output Export
=============================================================================*/


/*-----------------------------------------------------------------------------
  MODULE 1: GLOBAL MACRO PARAMETERS & LIBRARY SETUP
-----------------------------------------------------------------------------*/

%let REPORT_DATE    = 20240331;
%let REPORT_QTR     = 2024Q1;
%let SNAPSHOT_MONTH = 202403;
%let BASE_PATH      = /data/freddie/sfloans;
%let OUT_PATH       = /data/freddie/output;
%let REF_PATH       = /data/freddie/reference;
%let CUTOFF_DPD     = 90;          /* Days past due threshold for default    */
%let MIN_FICO       = 300;
%let MAX_FICO       = 850;
%let LTV_CAP        = 105;         /* Max LTV% for non-HARP loans            */
%let ECL_DISC_RATE  = 0.05;        /* Discount rate for ECL                  */
%let VINTAGE_START  = 2018;
%let VINTAGE_END    = 2024;

libname SFLOANS  "&BASE_PATH.";
libname OUTLIB   "&OUT_PATH.";
libname REFLIB   "&REF_PATH.";
libname WORK     WORK;

options compress=yes mprint mlogic symbolgen
        obs=MAX errors=20 pageno=1
        fmtsearch=(REFLIB WORK);

/*-----------------------------------------------------------------------------
  MODULE 2: DEFINE CUSTOM FORMATS (LOOKUP / MAPPING TABLES)
-----------------------------------------------------------------------------*/

proc format library=WORK;

  /* FICO Score Banding */
  value FICO_BAND
    300  - 579  = '1_SubPrime (<580)'
    580  - 619  = '2_NearPrime (580-619)'
    620  - 659  = '3_FairCredit (620-659)'
    660  - 719  = '4_GoodCredit (660-719)'
    720  - 759  = '5_VeryGood (720-759)'
    760  - 850  = '6_Excellent (760-850)'
    other       = '0_Unknown'
  ;

  /* LTV Banding */
  value LTV_BAND
    low  -  60  = '1_<=60%'
    60   <-  75  = '2_60-75%'
    75   <-  80  = '3_75-80%'
    80   <-  90  = '4_80-90%'
    90   <-  95  = '5_90-95%'
    95   <-  97  = '6_95-97%'
    97   <- high = '7_>97% (High Risk)'
    other        = '0_Unknown'
  ;

  /* Delinquency Status Buckets */
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

  /* Loan Purpose */
  value $LOAN_PURPOSE
    'P'  = 'Purchase'
    'C'  = 'Cash-Out Refi'
    'N'  = 'Rate-Term Refi'
    'U'  = 'Unknown'
    other= 'Other'
  ;

  /* Occupancy Type */
  value $OCC_TYPE
    'P'  = 'Primary Residence'
    'S'  = 'Second Home'
    'I'  = 'Investment Property'
    other= 'Unknown'
  ;

  /* Property Type */
  value $PROP_TYPE
    'SF' = 'Single Family'
    'PU' = 'PUD'
    'CO' = 'Condo'
    'MH' = 'Manufactured Housing'
    '2F' = '2-4 Unit'
    other= 'Other'
  ;

  /* Loan Channel */
  value $CHANNEL
    'R'  = 'Retail'
    'B'  = 'Broker'
    'C'  = 'Correspondent'
    'T'  = 'TPO'
    other= 'Unknown'
  ;

  /* Modification Flag */
  value $MOD_FLAG
    'Y'  = 'Modified'
    'N'  = 'Not Modified'
    other= 'Unknown'
  ;

  /* Geographic Region */
  value $STATE_REGION
    'CA','WA','OR','NV','AZ','HI','AK','ID','UT','MT','WY','CO','NM' = 'West'
    'TX','OK','KS','NE','SD','ND','MN','IA','MO','AR','LA'            = 'South Central'
    'FL','GA','SC','NC','VA','TN','AL','MS','KY','WV'                 = 'Southeast'
    'NY','NJ','CT','MA','RI','VT','NH','ME','PA','MD','DE','DC'       = 'Northeast'
    'OH','MI','IN','IL','WI'                                           = 'Midwest'
    other                                                               = 'Other'
  ;

run;


/*-----------------------------------------------------------------------------
  MODULE 3: NESTED MACRO - DATA STAGING & CLEANSING PIPELINE
-----------------------------------------------------------------------------*/

/* Macro: Validate and clip numeric field within bounds */
%macro clip_field(ds=, var=, lo=, hi=, newvar=);
  data &ds.;
    set &ds.;
    if &var. < &lo. then &newvar. = &lo.;
    else if &var. > &hi. then &newvar. = &hi.;
    else &newvar. = &var.;
  run;
%mend clip_field;

/* Macro: Derive snapshot month label */
%macro snap_label(yyyymm);
  %let yr = %substr(&yyyymm., 1, 4);
  %let mo = %substr(&yyyymm., 5, 2);
  %let snap_lbl = &yr.-&mo.;
%mend snap_label;

/* Macro: Stage one monthly loan file */
%macro stage_monthly_loan_file(snap_month=, src_lib=, out_lib=);

  %snap_label(&snap_month.);

  /* Step 1: Load raw origination + performance merge */
  data work.raw_&snap_month.;
    set &src_lib..sfperf_&snap_month. (
      keep = loan_id seller_name servicer_name orig_upb
             curr_upb orig_rate curr_rate orig_term
             rem_term orig_date maturity_date
             fico_orig ltv_orig cltv_orig
             dti_ratio purpose occupancy prop_type
             num_units channel state zip_code
             loan_age dpd_count zero_bal_code
             mod_flag harp_flag relief_refi_flag
             monthly_income monthly_payment
             prop_val_orig prop_val_curr
    );

    /* Derived fields */
    format snap_month 8. snap_label $7.;
    snap_month  = &snap_month.;
    snap_label  = "&snap_lbl.";

    /* LTV current (using updated property value if available) */
    if prop_val_curr > 0 then curr_ltv = (curr_upb / prop_val_curr) * 100;
    else if prop_val_orig > 0 then curr_ltv = (curr_upb / prop_val_orig) * 100;
    else curr_ltv = .;

    /* DTI flag */
    if dti_ratio > 43 then high_dti_flag = 1; else high_dti_flag = 0;

    /* Payment-to-income ratio */
    if monthly_income > 0 then pti_ratio = (monthly_payment / monthly_income) * 100;
    else pti_ratio = .;

    /* Curtailment / prepay indicator */
    if zero_bal_code in (01, 09) then prepay_flag = 1; else prepay_flag = 0;
    if zero_bal_code in (03, 06) then default_flag = 1; else default_flag = 0;
    if zero_bal_code in (02)     then payoff_flag  = 1; else payoff_flag  = 0;

    /* Vintage Year */
    vintage_yr = year(orig_date);

    /* Loan Age bucket */
    if      loan_age <=  12 then age_band = '01_0-12mo';
    else if loan_age <=  24 then age_band = '02_13-24mo';
    else if loan_age <=  36 then age_band = '03_25-36mo';
    else if loan_age <=  60 then age_band = '04_37-60mo';
    else if loan_age <= 120 then age_band = '05_61-120mo';
    else                         age_band = '06_120mo+';

    /* State region mapping via format */
    state_region = put(state, $STATE_REGION.);

    label
      loan_id      = 'Unique Loan Identifier'
      curr_upb     = 'Current Unpaid Principal Balance'
      curr_ltv     = 'Current LTV%'
      dpd_count    = 'Days Past Due'
      vintage_yr   = 'Origination Vintage Year'
      pti_ratio    = 'Payment-to-Income Ratio'
      state_region = 'Geographic Region'
    ;

  run;

  /* Step 2: Clip FICO and LTV to valid ranges */
  %clip_field(ds=work.raw_&snap_month., var=fico_orig, lo=&MIN_FICO., hi=&MAX_FICO., newvar=fico_clean);
  %clip_field(ds=work.raw_&snap_month., var=curr_ltv,  lo=0,           hi=200,        newvar=ltv_clean);

  /* Step 3: Apply format-based banding */
  data &out_lib..staged_&snap_month.;
    set work.raw_&snap_month.;
    fico_band  = put(fico_clean, FICO_BAND.);
    ltv_band   = put(ltv_clean,  LTV_BAND.);
    dpd_bucket = put(dpd_count,  DPD_BUCKET.);
    purpose_lbl= put(purpose,    $LOAN_PURPOSE.);
    occ_lbl    = put(occupancy,  $OCC_TYPE.);
    prop_lbl   = put(prop_type,  $PROP_TYPE.);
    channel_lbl= put(channel,    $CHANNEL.);
    mod_lbl    = put(mod_flag,   $MOD_FLAG.);
  run;

  /* Step 4: Print summary for QA */
  proc means data=&out_lib..staged_&snap_month. n nmiss mean min max stddev
    maxdec=2;
    var curr_upb fico_clean ltv_clean curr_ltv dti_ratio pti_ratio dpd_count loan_age;
    title "QA Summary: Snapshot &snap_lbl.";
  run;

%mend stage_monthly_loan_file;


/* Macro: Loop over multiple months */
%macro run_staging_pipeline(start_snap=, end_snap=, src_lib=, out_lib=);
  %local i snap;
  /* Build list of YYYYMM values between start and end */
  %let i = &start_snap.;
  %do %while (&i. <= &end_snap.);
    %stage_monthly_loan_file(snap_month=&i., src_lib=&src_lib., out_lib=&out_lib.);
    /* Increment month */
    %let yr = %substr(&i.,1,4);
    %let mo = %substr(&i.,5,2);
    %if &mo. = 12 %then %do;
      %let mo = 01;
      %let yr = %eval(&yr. + 1);
    %end;
    %else %let mo = %sysfunc(putn(%eval(&mo.+1), z2.));
    %let i = &yr.&mo.;
  %end;
%mend run_staging_pipeline;

/* Execute staging for last 4 quarters */
%run_staging_pipeline(
  start_snap = 202301,
  end_snap   = &SNAPSHOT_MONTH.,
  src_lib    = SFLOANS,
  out_lib    = OUTLIB
);


/*-----------------------------------------------------------------------------
  MODULE 4: COMBINE STAGED SNAPSHOTS INTO PANEL DATASET
-----------------------------------------------------------------------------*/

data OUTLIB.loan_panel;
  set OUTLIB.staged_202301
      OUTLIB.staged_202302
      OUTLIB.staged_202303
      OUTLIB.staged_202306
      OUTLIB.staged_202309
      OUTLIB.staged_202312
      OUTLIB.staged_202403
  ;
  by loan_id snap_month;
run;

proc sort data=OUTLIB.loan_panel; by loan_id snap_month; run;


/*-----------------------------------------------------------------------------
  MODULE 5: SQL-BASED PORTFOLIO AGGREGATION & DELINQUENCY ROLL RATES
-----------------------------------------------------------------------------*/

/* 5a. Current snapshot portfolio summary by state and FICO band */
proc sql;
  create table OUTLIB.portfolio_summary_&SNAPSHOT_MONTH. as
  select
    state,
    state_region,
    fico_band,
    ltv_band,
    dpd_bucket,
    purpose_lbl                        as loan_purpose,
    occ_lbl                            as occupancy_type,
    prop_lbl                           as property_type,
    channel_lbl                        as origination_channel,
    count(distinct loan_id)            as loan_count         format=comma12.,
    sum(curr_upb)                      as total_upb          format=dollar20.2,
    mean(curr_upb)                     as avg_upb            format=dollar16.2,
    mean(fico_clean)                   as avg_fico           format=8.1,
    mean(ltv_clean)                    as avg_curr_ltv       format=8.2,
    mean(dti_ratio)                    as avg_dti            format=8.2,
    mean(pti_ratio)                    as avg_pti            format=8.2,
    mean(loan_age)                     as avg_loan_age_mo    format=8.1,
    sum(curr_upb * (dpd_count >= 30))  as upb_dq30_plus      format=dollar20.2,
    sum(curr_upb * (dpd_count >= 60))  as upb_dq60_plus      format=dollar20.2,
    sum(curr_upb * (dpd_count >= 90))  as upb_dq90_plus      format=dollar20.2,
    calculated upb_dq30_plus / calculated total_upb * 100
                                       as dq30_rate_pct      format=8.4,
    calculated upb_dq60_plus / calculated total_upb * 100
                                       as dq60_rate_pct      format=8.4,
    calculated upb_dq90_plus / calculated total_upb * 100
                                       as dq90_rate_pct      format=8.4,
    sum(default_flag)                  as default_count      format=comma10.,
    sum(prepay_flag)                   as prepay_count       format=comma10.,
    sum(curr_upb * default_flag)       as default_upb        format=dollar20.2,
    sum(curr_upb * prepay_flag)        as prepay_upb         format=dollar20.2,
    sum(high_dti_flag)                 as high_dti_loans     format=comma10.,
    sum(mod_flag = 'Y')                as modified_loans     format=comma10.
  from OUTLIB.staged_&SNAPSHOT_MONTH.
  where snap_month = &SNAPSHOT_MONTH.
  group by
    state, state_region, fico_band, ltv_band, dpd_bucket,
    purpose_lbl, occ_lbl, prop_lbl, channel_lbl
  order by
    state_region, state, fico_band, ltv_band, dpd_bucket
  ;
quit;


/* 5b. Vintage cohort performance (delinquency by origination year & age) */
proc sql;
  create table OUTLIB.vintage_cohort_perf as
  select
    vintage_yr,
    age_band,
    count(distinct loan_id)                     as loan_count,
    sum(curr_upb)                               as total_upb      format=dollar22.2,
    mean(fico_clean)                            as avg_fico       format=8.1,
    mean(ltv_clean)                             as avg_ltv        format=8.2,
    sum(case when dpd_count >= 30  then 1 else 0 end) as cnt_dq30,
    sum(case when dpd_count >= 60  then 1 else 0 end) as cnt_dq60,
    sum(case when dpd_count >= 90  then 1 else 0 end) as cnt_dq90,
    sum(case when dpd_count >= 180 then 1 else 0 end) as cnt_dq180,
    calculated cnt_dq30  / calculated loan_count * 100 as dq30_rate  format=8.4,
    calculated cnt_dq60  / calculated loan_count * 100 as dq60_rate  format=8.4,
    calculated cnt_dq90  / calculated loan_count * 100 as dq90_rate  format=8.4,
    calculated cnt_dq180 / calculated loan_count * 100 as dq180_rate format=8.4,
    sum(default_flag)                           as defaults,
    sum(prepay_flag)                            as prepays,
    calculated defaults / calculated loan_count * 100 as cdr_pct    format=8.4,
    calculated prepays  / calculated loan_count * 100 as cpr_pct    format=8.4
  from OUTLIB.loan_panel
  where vintage_yr between &VINTAGE_START. and &VINTAGE_END.
  group by vintage_yr, age_band
  order by vintage_yr, age_band
  ;
quit;


/* 5c. Roll Rate Matrix: DPD Bucket to DPD Bucket (Month-over-Month) */
proc sql;
  create table OUTLIB.roll_rate_matrix as
  select
    a.dpd_bucket as dpd_from,
    b.dpd_bucket as dpd_to,
    count(*)     as loan_count,
    sum(b.curr_upb) as upb_rolled    format=dollar20.2
  from OUTLIB.loan_panel a
  inner join OUTLIB.loan_panel b
    on  a.loan_id    = b.loan_id
    and b.snap_month = ( select min(c.snap_month)
                         from OUTLIB.loan_panel c
                         where c.loan_id    = a.loan_id
                           and c.snap_month > a.snap_month )
  group by a.dpd_bucket, b.dpd_bucket
  order by a.dpd_bucket, b.dpd_bucket
  ;
quit;


/*-----------------------------------------------------------------------------
  MODULE 6: PROBABILITY OF DEFAULT (PD) SCORING — MACRO-DRIVEN
-----------------------------------------------------------------------------*/

/*
  Simplified logistic PD score using key risk drivers.
  Real Freddie models use econometric calibration with macro overlays.
  Coefficients here are illustrative.
*/

%macro compute_pd_score(inds=, outds=);

  data &outds.;
    set &inds.;

    /* Log-odds intercept */
    logit_pd = -6.50;

    /* FICO contribution (inverse — lower FICO = higher PD) */
    if fico_clean ne . then logit_pd = logit_pd + (-0.008 * fico_clean);

    /* Current LTV contribution */
    if ltv_clean ne . then logit_pd = logit_pd + (0.020 * ltv_clean);

    /* DTI contribution */
    if dti_ratio ne . then logit_pd = logit_pd + (0.015 * dti_ratio);

    /* Loan age (seasoning reduces PD up to a point) */
    if loan_age ne . then do;
      if loan_age <= 36 then logit_pd = logit_pd + (-0.010 * loan_age);
      else                   logit_pd = logit_pd + (0.002  * (loan_age - 36));
    end;

    /* Delinquency status (strong predictor) */
    select (dpd_bucket);
      when ('00_Current')      logit_pd = logit_pd + 0.00;
      when ('01_DPD01-29')     logit_pd = logit_pd + 1.20;
      when ('02_DPD30-59')     logit_pd = logit_pd + 2.50;
      when ('03_DPD60-89')     logit_pd = logit_pd + 3.80;
      when ('04_DPD90-119')    logit_pd = logit_pd + 5.20;
      when ('05_DPD120-179')   logit_pd = logit_pd + 6.00;
      when ('06_DPD180+')      logit_pd = logit_pd + 7.50;
      otherwise                logit_pd = logit_pd + 0.50;
    end;

    /* Occupancy risk add-on */
    select (occupancy);
      when ('P') logit_pd = logit_pd + 0.00;
      when ('S') logit_pd = logit_pd + 0.30;
      when ('I') logit_pd = logit_pd + 0.65;
      otherwise  logit_pd = logit_pd + 0.20;
    end;

    /* Loan purpose risk add-on */
    select (purpose);
      when ('P') logit_pd = logit_pd + 0.00;
      when ('N') logit_pd = logit_pd + 0.10;
      when ('C') logit_pd = logit_pd + 0.25;
      otherwise  logit_pd = logit_pd + 0.15;
    end;

    /* Modification overlay */
    if mod_flag = 'Y' then logit_pd = logit_pd + 0.80;

    /* Convert log-odds to probability */
    pd_score = 1 / (1 + exp(-logit_pd));

    /* PD Risk Tier */
    if      pd_score < 0.005 then pd_tier = '1_Very Low (<0.5%)';
    else if pd_score < 0.020 then pd_tier = '2_Low (0.5-2%)';
    else if pd_score < 0.050 then pd_tier = '3_Moderate (2-5%)';
    else if pd_score < 0.100 then pd_tier = '4_Elevated (5-10%)';
    else if pd_score < 0.200 then pd_tier = '5_High (10-20%)';
    else                          pd_tier = '6_Very High (20%+)';

    label
      logit_pd = 'Log-Odds of Default'
      pd_score = 'Probability of Default (12-month)'
      pd_tier  = 'PD Risk Tier'
    ;
    format pd_score percent8.4;

  run;

%mend compute_pd_score;

%compute_pd_score(
  inds = OUTLIB.staged_&SNAPSHOT_MONTH.,
  outds= OUTLIB.pd_scored_&SNAPSHOT_MONTH.
);


/*-----------------------------------------------------------------------------
  MODULE 7: LOSS GIVEN DEFAULT (LGD) ESTIMATION
-----------------------------------------------------------------------------*/

%macro compute_lgd(inds=, outds=);

  data &outds.;
    set &inds.;

    /*
      LGD Model:
        Base LGD driven by LTV (higher LTV = less collateral coverage)
        Adjusted for property type, state foreclosure timeline, and modification
    */

    /* Base LGD from LTV */
    if ltv_clean <= 60      then base_lgd = 0.10;
    else if ltv_clean <= 75 then base_lgd = 0.18;
    else if ltv_clean <= 80 then base_lgd = 0.22;
    else if ltv_clean <= 90 then base_lgd = 0.30;
    else if ltv_clean <= 97 then base_lgd = 0.38;
    else                         base_lgd = 0.48;

    /* Foreclosure timeline adjustment by state (illustrative, judicial vs non) */
    if state in ('NY','NJ','FL','IL','CT','HI','IN','KS','KY','LA','ME',
                 'ND','OH','OK','PA','SC','ND','VT','WI') then
         fc_adj = 0.05;   /* Judicial — longer timeline, higher carrying cost */
    else fc_adj = 0.00;   /* Non-judicial */

    /* Property type adjustment */
    select (prop_type);
      when ('SF') prop_adj = 0.00;
      when ('CO') prop_adj = 0.03;
      when ('PU') prop_adj = 0.02;
      when ('MH') prop_adj = 0.08;
      when ('2F') prop_adj = 0.04;
      otherwise   prop_adj = 0.05;
    end;

    /* Modification benefit (recoveries tend to be higher post-mod) */
    if mod_flag = 'Y' then mod_adj = -0.03; else mod_adj = 0.00;

    /* Final LGD (capped at 100%) */
    lgd_estimate = min(1, base_lgd + fc_adj + prop_adj + mod_adj);

    label lgd_estimate = 'Loss Given Default Estimate';
    format lgd_estimate percent8.4;

  run;

%mend compute_lgd;

%compute_lgd(
  inds  = OUTLIB.pd_scored_&SNAPSHOT_MONTH.,
  outds = OUTLIB.lgd_scored_&SNAPSHOT_MONTH.
);


/*-----------------------------------------------------------------------------
  MODULE 8: EXPECTED CREDIT LOSS (ECL) COMPUTATION
-----------------------------------------------------------------------------*/

%macro compute_ecl(inds=, outds=);

  data &outds.;
    set &inds.;

    /* EAD = Exposure at Default = Current UPB (simplified, no CCF) */
    ead = curr_upb;

    /* 12-month ECL = PD x LGD x EAD */
    ecl_12mo = pd_score * lgd_estimate * ead;

    /* Lifetime ECL (simplified: extend PD using survival model assumption) */
    /* Remaining life in years */
    rem_life_yrs = rem_term / 12;

    /* Cumulative PD over remaining life (simplified annuity approach) */
    if pd_score < 1 then
      cum_pd = 1 - (1 - pd_score) ** rem_life_yrs;
    else cum_pd = 1;

    /* Discounted lifetime ECL */
    if &ECL_DISC_RATE. > 0 and rem_life_yrs > 0 then
      ecl_lifetime = cum_pd * lgd_estimate * ead
                     * ( (1 - (1 + &ECL_DISC_RATE.) ** (-rem_life_yrs))
                         / &ECL_DISC_RATE. )
                     / rem_life_yrs;
    else
      ecl_lifetime = cum_pd * lgd_estimate * ead;

    /* Stage classification (IFRS 9 / CECL analog) */
    if      dpd_count = 0 and pd_score < 0.02  then ifrs9_stage = 'Stage 1 - Performing';
    else if dpd_count < 90 or pd_score < 0.20  then ifrs9_stage = 'Stage 2 - Underperforming';
    else                                             ifrs9_stage = 'Stage 3 - Credit-Impaired';

    /* ECL Coverage Ratio */
    if curr_upb > 0 then ecl_coverage_pct = ecl_12mo / curr_upb * 100;
    else ecl_coverage_pct = .;

    label
      ead             = 'Exposure at Default'
      ecl_12mo        = '12-Month Expected Credit Loss'
      ecl_lifetime    = 'Lifetime Expected Credit Loss'
      cum_pd          = 'Cumulative PD over Remaining Life'
      ifrs9_stage     = 'IFRS 9 / CECL Stage Classification'
      ecl_coverage_pct= 'ECL as % of UPB (Coverage Ratio)'
    ;
    format
      ead          dollar20.2
      ecl_12mo     dollar16.2
      ecl_lifetime dollar16.2
      cum_pd       percent8.4
      ecl_coverage_pct 8.4
    ;

  run;

%mend compute_ecl;

%compute_ecl(
  inds  = OUTLIB.lgd_scored_&SNAPSHOT_MONTH.,
  outds = OUTLIB.ecl_final_&SNAPSHOT_MONTH.
);


/*-----------------------------------------------------------------------------
  MODULE 9: ECL PORTFOLIO SUMMARY ROLLUP
-----------------------------------------------------------------------------*/

proc sql;
  create table OUTLIB.ecl_summary_by_segment as
  select
    ifrs9_stage,
    pd_tier,
    fico_band,
    ltv_band,
    state_region,
    count(distinct loan_id)         as loan_count          format=comma12.,
    sum(curr_upb)                   as total_upb           format=dollar22.2,
    sum(ecl_12mo)                   as total_ecl_12mo      format=dollar22.2,
    sum(ecl_lifetime)               as total_ecl_life      format=dollar22.2,
    mean(pd_score)                  as avg_pd              format=percent8.4,
    mean(lgd_estimate)              as avg_lgd             format=percent8.4,
    mean(ecl_coverage_pct)          as avg_ecl_cov_pct     format=8.4,
    calculated total_ecl_12mo
      / calculated total_upb * 100  as ecl_rate_pct        format=8.4,
    sum(case when ifrs9_stage contains 'Stage 3' then curr_upb else 0 end)
                                    as npl_upb             format=dollar20.2,
    calculated npl_upb
      / calculated total_upb * 100  as npl_rate_pct        format=8.4
  from OUTLIB.ecl_final_&SNAPSHOT_MONTH.
  group by ifrs9_stage, pd_tier, fico_band, ltv_band, state_region
  order by ifrs9_stage, pd_tier, fico_band, ltv_band, state_region
  ;
quit;


/*-----------------------------------------------------------------------------
  MODULE 10: MACRO — NESTED COHORT ROLL RATE REPORT
-----------------------------------------------------------------------------*/

%macro roll_rate_report(cohort_start=, cohort_end=, out_prefix=);

  /* Build consecutive month pairs for roll rate */
  proc sql noprint;
    select distinct snap_month into :snap_list separated by ' '
    from OUTLIB.loan_panel
    where snap_month between &cohort_start. and &cohort_end.
    order by snap_month;
  quit;

  %let n_snaps = %sysfunc(countw(&snap_list.));

  %do i = 1 %to %eval(&n_snaps. - 1);
    %let snap_t0 = %scan(&snap_list., &i.);
    %let snap_t1 = %scan(&snap_list., %eval(&i.+1));

    proc sql;
      create table work.roll_&snap_t0._&snap_t1. as
      select
        a.dpd_bucket                            as dpd_from     label='DPD Bucket (T)',
        b.dpd_bucket                            as dpd_to       label='DPD Bucket (T+1)',
        "&snap_t0.->&snap_t1."                  as period       label='Roll Period',
        count(distinct a.loan_id)               as loan_count,
        sum(b.curr_upb)                         as upb_end      format=dollar20.2,
        count(*) / sum(count(*)) over
          (partition by a.dpd_bucket) * 100     as roll_rate_pct format=8.2
      from OUTLIB.loan_panel a
      inner join OUTLIB.loan_panel b
        on a.loan_id = b.loan_id
       and a.snap_month = &snap_t0.
       and b.snap_month = &snap_t1.
      group by a.dpd_bucket, b.dpd_bucket
      order by a.dpd_bucket, b.dpd_bucket
      ;
    quit;

  %end;

  /* Stack all roll rate periods */
  data OUTLIB.&out_prefix._roll_rates;
    set work.roll_:;
  run;

  proc sort data=OUTLIB.&out_prefix._roll_rates;
    by period dpd_from dpd_to;
  run;

%mend roll_rate_report;

%roll_rate_report(
  cohort_start = 202301,
  cohort_end   = &SNAPSHOT_MONTH.,
  out_prefix   = fm_sf
);


/*-----------------------------------------------------------------------------
  MODULE 11: STRESS TESTING — MACRO-PARAMETERIZED SCENARIOS
-----------------------------------------------------------------------------*/

%macro stress_test(inds=, outds=, scenario=BASE,
                   fico_shock=0, ltv_shock=0, unemp_pd_mult=1.0,
                   hpa_pct=0);

  data &outds.;
    set &inds.;

    /* Apply shocks */
    fico_stressed = max(&MIN_FICO., fico_clean + &fico_shock.);
    ltv_stressed  = min(200, ltv_clean  - &hpa_pct. + &ltv_shock.);
                    /* hpa_pct > 0 means HPA (lowers LTV), shock adds stress */

    /* Re-derive stressed PD (simplified re-run of key drivers) */
    logit_pd_stress = -6.50
      + (-0.008 * fico_stressed)
      + (0.020  * ltv_stressed)
      + (0.015  * dti_ratio);

    if dpd_count >= 90 then logit_pd_stress = logit_pd_stress + 5.20;
    else if dpd_count >= 60 then logit_pd_stress = logit_pd_stress + 3.80;
    else if dpd_count >= 30 then logit_pd_stress = logit_pd_stress + 2.50;

    pd_stress   = min(1, &unemp_pd_mult. / (1 + exp(-logit_pd_stress)));

    /* Stressed LGD — HPA deterioration increases loss */
    lgd_stress  = min(1, lgd_estimate + (max(0, ltv_stressed - 80) * 0.005));

    /* Stressed ECL */
    ecl_stress  = pd_stress * lgd_stress * ead;

    ecl_delta   = ecl_stress - ecl_12mo;   /* Stress incremental loss */
    scenario_lbl= "&scenario.";

    format pd_stress lgd_stress percent8.4
           ecl_stress ecl_delta dollar16.2;

  run;

%mend stress_test;

/* Run 3 scenarios: Base, Adverse, Severely Adverse */
%stress_test(
  inds=OUTLIB.ecl_final_&SNAPSHOT_MONTH., outds=OUTLIB.stress_base,
  scenario=BASE, fico_shock=0, ltv_shock=0, unemp_pd_mult=1.0, hpa_pct=3
);

%stress_test(
  inds=OUTLIB.ecl_final_&SNAPSHOT_MONTH., outds=OUTLIB.stress_adverse,
  scenario=ADVERSE, fico_shock=-30, ltv_shock=8, unemp_pd_mult=1.8, hpa_pct=-5
);

%stress_test(
  inds=OUTLIB.ecl_final_&SNAPSHOT_MONTH., outds=OUTLIB.stress_severe,
  scenario=SEVERELY_ADVERSE, fico_shock=-60, ltv_shock=20, unemp_pd_mult=3.0, hpa_pct=-15
);

/* Stack scenarios for comparison */
data OUTLIB.stress_scenarios_combined;
  set OUTLIB.stress_base
      OUTLIB.stress_adverse
      OUTLIB.stress_severe;
  by scenario_lbl;
run;

/* Scenario summary */
proc sql;
  create table OUTLIB.stress_summary as
  select
    scenario_lbl,
    count(distinct loan_id)   as loan_count     format=comma12.,
    sum(curr_upb)             as total_upb       format=dollar22.2,
    sum(ecl_12mo)             as ecl_base        format=dollar22.2,
    sum(ecl_stress)           as ecl_stressed    format=dollar22.2,
    sum(ecl_delta)            as ecl_stress_lift format=dollar22.2,
    calculated ecl_stress_lift / calculated total_upb * 100
                              as stress_rate_bps format=8.2,
    mean(pd_stress)           as avg_pd_stress   format=percent8.4,
    mean(lgd_stress)          as avg_lgd_stress  format=percent8.4
  from OUTLIB.stress_scenarios_combined
  group by scenario_lbl
  order by scenario_lbl
  ;
quit;


/*-----------------------------------------------------------------------------
  MODULE 12: STATE-LEVEL NPL HEATMAP SUMMARY
-----------------------------------------------------------------------------*/

proc sql;
  create table OUTLIB.state_npl_summary as
  select
    state,
    state_region,
    count(distinct loan_id)                              as loan_count,
    sum(curr_upb)                                        as total_upb       format=dollar20.2,
    sum(case when dpd_count >= 90 then curr_upb else 0 end)
                                                         as npl_upb         format=dollar20.2,
    calculated npl_upb / calculated total_upb * 100      as npl_rate        format=8.4,
    sum(ecl_12mo)                                        as total_ecl       format=dollar20.2,
    calculated total_ecl / calculated total_upb * 100    as ecl_coverage    format=8.4,
    mean(pd_score)                                       as avg_pd          format=percent8.4,
    mean(lgd_estimate)                                   as avg_lgd         format=percent8.4,
    mean(fico_clean)                                     as avg_fico        format=8.1,
    mean(ltv_clean)                                      as avg_ltv         format=8.2,
    sum(case when ifrs9_stage contains 'Stage 3'
             then 1 else 0 end)                          as stage3_count
  from OUTLIB.ecl_final_&SNAPSHOT_MONTH.
  group by state, state_region
  order by npl_rate desc
  ;
quit;


/*-----------------------------------------------------------------------------
  MODULE 13: FINAL REPORT OUTPUTS
-----------------------------------------------------------------------------*/

/* 13a. Executive Summary — Top-Level ECL by IFRS9 Stage */
proc tabulate data=OUTLIB.ecl_final_&SNAPSHOT_MONTH. missing;
  class  ifrs9_stage pd_tier state_region;
  var    curr_upb ecl_12mo ecl_lifetime pd_score lgd_estimate;
  table  ifrs9_stage * pd_tier,
         state_region * (
           curr_upb    * (sum*f=dollar18. mean*f=dollar14.)
           ecl_12mo    * (sum*f=dollar16. mean*f=dollar12.)
           pd_score    * mean*f=percent8.4
           lgd_estimate* mean*f=percent8.4
         );
  title  "Freddie Mac SF Loan Portfolio — ECL Summary by Stage & Tier";
  title2 "Report Date: &REPORT_DATE. | Snapshot: &SNAPSHOT_MONTH.";
run;

/* 13b. Export all output tables to CSV for Python consumption */

%macro export_to_csv(ds=, outfile=);
  proc export data=&ds.
    outfile="&OUT_PATH./&outfile..csv"
    dbms=csv replace;
  run;
%mend export_to_csv;

%export_to_csv(ds=OUTLIB.portfolio_summary_&SNAPSHOT_MONTH., outfile=portfolio_summary);
%export_to_csv(ds=OUTLIB.ecl_summary_by_segment,             outfile=ecl_by_segment);
%export_to_csv(ds=OUTLIB.vintage_cohort_perf,                outfile=vintage_cohort);
%export_to_csv(ds=OUTLIB.fm_sf_roll_rates,                   outfile=roll_rates);
%export_to_csv(ds=OUTLIB.state_npl_summary,                  outfile=state_npl);
%export_to_csv(ds=OUTLIB.stress_summary,                     outfile=stress_scenarios);

/* 13c. Final completion log */
data _null_;
  today = put(date(), worddate18.);
  put "====================================================";
  put "  Freddie Mac Mortgage Analytics Pipeline COMPLETE";
  put "  Snapshot Month : &SNAPSHOT_MONTH.";
  put "  Report Date    : &REPORT_DATE.";
  put "  Run Timestamp  : " today;
  put "====================================================";
run;

/*=============================================================================
  END OF PROGRAM
=============================================================================*/
