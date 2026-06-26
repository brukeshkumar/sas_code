/*=============================================================================
  File    : reporting/14_final_exports.sas
  Purpose : Export all final output datasets to CSV for Python consumption.
            Files land in &OUT_PATH. for the SAS-to-Python pipeline.
=============================================================================*/

%put NOTE: [14_final_exports] Exporting all output tables to CSV.;

%export_to_csv(ds=OUTLIB.portfolio_summary_&SNAPSHOT_MONTH., outfile=portfolio_summary);
%export_to_csv(ds=OUTLIB.ecl_final_&SNAPSHOT_MONTH.,         outfile=ecl_loan_level);
%export_to_csv(ds=OUTLIB.ecl_summary_by_segment,             outfile=ecl_by_segment);
%export_to_csv(ds=OUTLIB.vintage_cohort_perf,                outfile=vintage_cohort);
%export_to_csv(ds=OUTLIB.roll_rate_latest,                   outfile=roll_rate_latest);
%export_to_csv(ds=OUTLIB.roll_rate_timeseries,               outfile=roll_rate_timeseries);
%export_to_csv(ds=OUTLIB.state_npl_summary,                  outfile=state_npl_heatmap);
%export_to_csv(ds=OUTLIB.stress_scenario_summary,            outfile=stress_scenario_summary);
%export_to_csv(ds=OUTLIB.stress_all_scenarios,               outfile=stress_all_scenarios);

%put NOTE: [14_final_exports] All exports complete.;
