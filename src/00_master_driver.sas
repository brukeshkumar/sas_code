/*=============================================================================
  FREDDIE MAC — MORTGAGE PORTFOLIO ANALYTICS SYSTEM
  File    : 00_master_driver.sas
  Purpose : Master orchestrator — calls all pipeline modules in sequence.
            Run this file to execute the full pipeline end-to-end.
  Team    : Finance & Credit Analytics
=============================================================================*/

/* ── 1. Global config & library setup ── */
%include "/pgm/config/01_global_config.sas";

/* ── 2. Custom formats & lookup maps ── */
%include "/pgm/config/02_formats_and_lookups.sas";

/* ── 3. Macro library (load all reusable macros) ── */
%include "/pgm/macros/mac_clip_field.sas";
%include "/pgm/macros/mac_snap_label.sas";
%include "/pgm/macros/mac_stage_monthly.sas";
%include "/pgm/macros/mac_run_staging_loop.sas";
%include "/pgm/macros/mac_pd_score.sas";
%include "/pgm/macros/mac_lgd_score.sas";
%include "/pgm/macros/mac_ecl_compute.sas";
%include "/pgm/macros/mac_stress_test.sas";
%include "/pgm/macros/mac_export_csv.sas";

/* ── 4. Data staging & panel build ── */
%include "/pgm/data_staging/03_stage_monthly_files.sas";
%include "/pgm/data_staging/04_build_loan_panel.sas";

/* ── 5. SQL aggregations ── */
%include "/pgm/sql/05_portfolio_summary_sql.sas";
%include "/pgm/sql/06_vintage_cohort_sql.sas";
%include "/pgm/sql/07_roll_rate_matrix_sql.sas";

/* ── 6. Credit risk scoring ── */
%include "/pgm/scoring/08_pd_scoring.sas";
%include "/pgm/scoring/09_lgd_scoring.sas";
%include "/pgm/scoring/10_ecl_computation.sas";

/* ── 7. Stress testing ── */
%include "/pgm/stress/11_stress_scenarios.sas";

/* ── 8. Reporting & export ── */
%include "/pgm/reporting/12_ecl_summary_report.sas";
%include "/pgm/reporting/13_state_npl_heatmap.sas";
%include "/pgm/reporting/14_final_exports.sas";

data _null_;
  put "=========================================";
  put "  PIPELINE COMPLETE — &REPORT_DATE.";
  put "=========================================";
run;
