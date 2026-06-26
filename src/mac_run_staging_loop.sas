/*=============================================================================
  File    : macros/mac_run_staging_loop.sas
  Purpose : Loop over a range of YYYYMM snapshots and call
            %stage_monthly_loan_file for each.
  Params  : start_snap= first YYYYMM (e.g. 202301)
            end_snap=   last  YYYYMM (e.g. 202403)
            src_lib=    source library
            out_lib=    output library
=============================================================================*/

%macro run_staging_pipeline(start_snap=, end_snap=, src_lib=, out_lib=);

  %local i_yr i_mo snap_curr;

  %let i_yr = %substr(&start_snap., 1, 4);
  %let i_mo = %substr(&start_snap., 5, 2);
  %let snap_curr = &start_snap.;

  %put NOTE: [run_staging_pipeline] Running &start_snap. → &end_snap.;

  %do %while (&snap_curr. <= &end_snap.);

    %stage_monthly_loan_file(
      snap_month = &snap_curr.,
      src_lib    = &src_lib.,
      out_lib    = &out_lib.
    );

    /* ── Increment month ── */
    %if &i_mo. = 12 %then %do;
      %let i_mo  = 01;
      %let i_yr  = %eval(&i_yr. + 1);
    %end;
    %else %let i_mo = %sysfunc(putn(%eval(&i_mo. + 1), z2.));

    %let snap_curr = &i_yr.&i_mo.;

  %end;

  %put NOTE: [run_staging_pipeline] All snapshots staged successfully.;

%mend run_staging_pipeline;
