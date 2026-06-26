/*=============================================================================
  File    : reporting/12_ecl_summary_report.sas
  Purpose : Executive-level ECL summary report using PROC TABULATE.
            Multi-dimensional breakdowns for Finance & Risk leadership.
=============================================================================*/

%put NOTE: [12_ecl_summary_report] Generating ECL summary report.;

/* ── Full multi-dim tabulation ── */
proc tabulate data=OUTLIB.ecl_final_&SNAPSHOT_MONTH. missing;
  class  ifrs9_lbl pd_tier state_region fico_band ltv_band;
  var    curr_upb ecl_12mo ecl_lifetime ecl_allowance
         pd_score lgd_estimate ecl_coverage_pct;
  table  ifrs9_lbl * pd_tier,
         state_region * (
           curr_upb      * ( sum*f=dollar18.  n*f=comma10. )
           ecl_allowance * ( sum*f=dollar16.            )
           pd_score      *   mean*f=percent8.4
           lgd_estimate  *   mean*f=percent8.4
           ecl_coverage_pct * mean*f=8.2
         )
         / box='ECL Summary by Stage, Tier, Region';
  title  "Freddie Mac SF Portfolio — ECL by IFRS9 Stage & PD Tier";
  title2 "Report Date: &REPORT_DATE. | Snapshot: &SNAPSHOT_MONTH.";
run;

/* ── Vintage × Stage cross-tab ── */
proc tabulate data=OUTLIB.ecl_final_&SNAPSHOT_MONTH. missing;
  class  vintage_yr ifrs9_lbl;
  var    curr_upb ecl_allowance pd_score;
  table  vintage_yr,
         ifrs9_lbl * (
           curr_upb      * sum*f=dollar16.
           ecl_allowance * sum*f=dollar14.
           pd_score      * mean*f=percent8.4
         );
  title "ECL by Origination Vintage and IFRS9 Stage";
run;

/* ── FICO Band × LTV Band heat-table ── */
proc tabulate data=OUTLIB.ecl_final_&SNAPSHOT_MONTH. missing;
  class  fico_band ltv_band;
  var    curr_upb ecl_allowance ecl_coverage_pct;
  table  fico_band,
         ltv_band * (
           curr_upb         * sum*f=dollar16.
           ecl_allowance    * sum*f=dollar14.
           ecl_coverage_pct * mean*f=8.2
         );
  title "ECL Coverage Heat Map — FICO Band × LTV Band";
run;

%put NOTE: [12_ecl_summary_report] Complete.;
