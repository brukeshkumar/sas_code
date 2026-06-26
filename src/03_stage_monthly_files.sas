/*=============================================================================
  File    : data_staging/03_stage_monthly_files.sas
  Purpose : Execute the monthly staging loop for all snapshots in scope.
            Calls %run_staging_pipeline which iterates %stage_monthly_loan_file.
=============================================================================*/

%put NOTE: [03_stage_monthly_files] Starting monthly staging loop.;

%run_staging_pipeline(
  start_snap = &STAGING_START.,
  end_snap   = &STAGING_END.,
  src_lib    = SFLOANS,
  out_lib    = OUTLIB
);

%put NOTE: [03_stage_monthly_files] Monthly staging complete.;
