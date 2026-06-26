/*=============================================================================
  File    : stress/11_stress_scenarios.sas
  Purpose : Execute BASE, ADVERSE, and SEVERELY_ADVERSE stress scenarios.
            Calls %stress_test for each. Stacks and summarizes results.
=============================================================================*/

%put NOTE: [11_stress_scenarios] Running DFAST-style stress scenarios.;

/* ── BASE ── */
%stress_test(
  inds          = OUTLIB.ecl_final_&SNAPSHOT_MONTH.,
  outds         = OUTLIB.stress_base,
  scenario      = BASE,
  fico_shock    = 0,
  ltv_shock     = 0,
  unemp_pd_mult = 1.0,
  hpa_pct       = 3       /* 3% HPA — mild appreciation */
);

/* ── ADVERSE ── */
%stress_test(
  inds          = OUTLIB.ecl_final_&SNAPSHOT_MONTH.,
  outds         = OUTLIB.stress_adverse,
  scenario      = ADVERSE,
  fico_shock    = -30,    /* FICO drops ~30 pts */
  ltv_shock     = 8,      /* LTV increases 8 pts */
  unemp_pd_mult = 1.8,    /* PD multiplied 1.8x for unemployment shock */
  hpa_pct       = -5      /* 5% HPA decline */
);

/* ── SEVERELY ADVERSE ── */
%stress_test(
  inds          = OUTLIB.ecl_final_&SNAPSHOT_MONTH.,
  outds         = OUTLIB.stress_severe,
  scenario      = SEVERELY_ADVERSE,
  fico_shock    = -60,    /* Significant credit score deterioration */
  ltv_shock     = 20,     /* Severe underwater scenario */
  unemp_pd_mult = 3.0,    /* PD triples (severe unemployment) */
  hpa_pct       = -15     /* 15% HPA decline (GFC-level) */
);

/* ── Stack scenarios ── */
data OUTLIB.stress_all_scenarios;
  set OUTLIB.stress_base
      OUTLIB.stress_adverse
      OUTLIB.stress_severe;
run;

/* ── Scenario comparison summary ── */
proc sql;
  create table OUTLIB.stress_scenario_summary as
  select
    scenario_lbl,
    count(distinct loan_id)                        as loan_count         format=comma12.,
    sum(curr_upb)                                  as total_upb          format=dollar22.2,
    sum(ecl_12mo)                                  as ecl_base           format=dollar22.2,
    sum(ecl_stress)                                as ecl_stressed       format=dollar22.2,
    sum(ecl_delta)                                 as ecl_stress_lift    format=dollar22.2,
    calculated ecl_stress_lift
      / calculated total_upb * 10000               as stress_lift_bps    format=8.1,
    mean(pd_stress)                                as avg_pd_stressed    format=percent8.4,
    mean(lgd_stress)                               as avg_lgd_stressed   format=percent8.4,
    sum(stage_migration)                           as stage_migrations   format=comma10.,
    calculated stage_migrations
      / calculated loan_count * 100                as migration_rate_pct format=8.2,
    sum(case when stressed_stage='S3' then 1 else 0 end)
                                                   as s3_count_stressed  format=comma10.
  from OUTLIB.stress_all_scenarios
  group by scenario_lbl
  order by scenario_lbl
  ;
quit;

proc print data=OUTLIB.stress_scenario_summary noobs;
  title "Freddie Mac SF Portfolio — Stress Scenario Comparison";
  title2 "Snapshot: &SNAPSHOT_MONTH.";
run;

%put NOTE: [11_stress_scenarios] Complete.;
