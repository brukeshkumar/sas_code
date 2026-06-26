/*=============================================================================
  File    : data_staging/04_build_loan_panel.sas
  Purpose : Stack all staged monthly snapshots into a longitudinal panel.
            Deduplicate, sort, and add panel-level derived fields.
=============================================================================*/

%put NOTE: [04_build_loan_panel] Building longitudinal loan panel.;

/* ── Stack all available staged snapshots ── */
data OUTLIB.loan_panel;
  set OUTLIB.staged_: ;   /* Wildcard: all OUTLIB.staged_YYYYMM datasets */
  by loan_id snap_month;
run;

proc sort data=OUTLIB.loan_panel nodupkey;
  by loan_id snap_month;
run;

/* ── Panel-level derived fields ── */
data OUTLIB.loan_panel;
  set OUTLIB.loan_panel;
  by loan_id;

  /* First/last observation flags */
  first_obs = first.loan_id;
  last_obs  = last.loan_id;

  /* Consecutive DPD worsening indicator */
  retain prev_dpd 0;
  if first.loan_id then prev_dpd = 0;
  dpd_worsened = (dpd_count > prev_dpd and not first.loan_id);
  prev_dpd = dpd_count;

  label
    first_obs    = 'First Observation for Loan'
    last_obs     = 'Last Observation for Loan'
    dpd_worsened = 'DPD Worsened vs Prior Period'
  ;

run;

/* ── Panel summary ── */
proc sql;
  select
    count(distinct loan_id) as unique_loans    format=comma12.,
    count(*)                as total_rows       format=comma14.,
    min(snap_month)         as earliest_snap,
    max(snap_month)         as latest_snap,
    mean(dpd_count)         as avg_dpd          format=8.2
  from OUTLIB.loan_panel;
quit;

%put NOTE: [04_build_loan_panel] Panel built → OUTLIB.loan_panel;
