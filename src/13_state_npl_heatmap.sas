/*=============================================================================
  File    : reporting/13_state_npl_heatmap.sas
  Purpose : State-level NPL and ECL summary for geographic risk heatmap.
            Ranks states by NPL rate and ECL coverage.
=============================================================================*/

%put NOTE: [13_state_npl_heatmap] Building state NPL heatmap summary.;

proc sql;
  create table OUTLIB.state_npl_summary as
  select
    state,
    state_region,
    fc_type,
    count(distinct loan_id)                                      as loan_count      format=comma12.,
    sum(curr_upb)                                                as total_upb       format=dollar22.2,
    sum(case when dpd_count >= 30  then curr_upb else 0 end)    as upb_dq30        format=dollar20.2,
    sum(case when dpd_count >= 90  then curr_upb else 0 end)    as npl_upb         format=dollar20.2,
    sum(case when dpd_count >= 180 then curr_upb else 0 end)    as sev_dq_upb      format=dollar20.2,
    calculated npl_upb    / calculated total_upb * 100          as npl_rate_pct    format=8.4,
    calculated upb_dq30   / calculated total_upb * 100          as dq30_rate_pct   format=8.4,
    sum(ecl_allowance)                                           as total_ecl       format=dollar20.2,
    calculated total_ecl  / calculated total_upb * 100          as ecl_coverage    format=8.4,
    mean(pd_score)                                               as avg_pd          format=percent8.4,
    mean(lgd_estimate)                                           as avg_lgd         format=percent8.4,
    mean(fico_clean)                                             as avg_fico        format=8.1,
    mean(ltv_clean)                                              as avg_ltv         format=8.2,
    mean(dti_clean)                                              as avg_dti         format=8.2,
    sum(case when ifrs9_stage = 'S3' then 1 else 0 end)         as stage3_count    format=comma10.,
    calculated stage3_count / calculated loan_count * 100       as stage3_rate_pct format=8.2,
    sum(default_flag)                                            as total_defaults  format=comma10.,
    sum(mod_flag = 'Y')                                          as total_mods      format=comma10.,

    /* Rank by NPL rate (dense_rank equivalent via window function) */
    count(distinct loan_id) /
      sum(count(distinct loan_id)) over () * 100                as pct_of_book     format=8.2

  from OUTLIB.ecl_final_&SNAPSHOT_MONTH.
  group by state, state_region, fc_type
  order by npl_rate_pct desc
  ;
quit;

/* Print top 15 states by NPL rate */
proc print data=OUTLIB.state_npl_summary (obs=15) noobs;
  var state state_region fc_type loan_count total_upb
      npl_rate_pct dq30_rate_pct ecl_coverage avg_pd avg_fico avg_ltv;
  title "Top 15 States by NPL Rate — &SNAPSHOT_MONTH.";
run;

%put NOTE: [13_state_npl_heatmap] Complete → OUTLIB.state_npl_summary;
