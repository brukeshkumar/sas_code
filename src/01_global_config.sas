/*=============================================================================
  File    : config/01_global_config.sas
  Purpose : Global macro variables, library definitions, system options.
            Sourced first by master driver.
=============================================================================*/

/* ── Report parameters ── */
%global REPORT_DATE REPORT_QTR SNAPSHOT_MONTH BASE_PATH OUT_PATH REF_PATH;
%global CUTOFF_DPD MIN_FICO MAX_FICO LTV_CAP ECL_DISC_RATE;
%global VINTAGE_START VINTAGE_END STAGING_START STAGING_END;

%let REPORT_DATE     = 20240331;
%let REPORT_QTR      = 2024Q1;
%let SNAPSHOT_MONTH  = 202403;
%let STAGING_START   = 202301;
%let STAGING_END     = 202403;

%let BASE_PATH       = /data/freddie/sfloans;
%let OUT_PATH        = /data/freddie/output;
%let REF_PATH        = /data/freddie/reference;

%let CUTOFF_DPD      = 90;
%let MIN_FICO        = 300;
%let MAX_FICO        = 850;
%let LTV_CAP         = 105;
%let ECL_DISC_RATE   = 0.05;
%let VINTAGE_START   = 2018;
%let VINTAGE_END     = 2024;

/* ── Library assignments ── */
libname SFLOANS  "&BASE_PATH.";
libname OUTLIB   "&OUT_PATH.";
libname REFLIB   "&REF_PATH.";

/* ── System options ── */
options compress    = yes
        mprint      = yes
        mlogic      = yes
        symbolgen   = yes
        obs         = MAX
        errors      = 20
        pageno      = 1
        fmtsearch   = (REFLIB WORK)
        nosource2;
