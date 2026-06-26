/*=============================================================================
  File    : scoring/10_ecl_computation.sas
  Purpose : Execute ECL computation and IFRS9 staging. Calls %compute_ecl.
=============================================================================*/
%compute_ecl(
  inds  = OUTLIB.lgd_scored_&SNAPSHOT_MONTH.,
  outds = OUTLIB.ecl_final_&SNAPSHOT_MONTH.
);

/* ECL by segment rollup */
proc sql;
  create table OUTLIB.ecl_summary_by_segment as
  select
    ifrs9_lbl,
    pd_tier,
    fico_band,
    ltv_band,
    state_region,
    count(distinct loan_id)                         as loan_count     format=comma12.,
    sum(curr_upb)                                   as total_upb      format=dollar22.2,
    sum(ecl_allowance)                              as total_ecl      format=dollar22.2,
    mean(pd_score)                                  as avg_pd         format=percent8.4,
    mean(lgd_estimate)                              as avg_lgd        format=percent8.4,
    mean(ecl_coverage_pct)                          as avg_coverage   format=8.4,
    calculated total_ecl / calculated total_upb * 100
                                                    as ecl_rate_pct   format=8.4
  from OUTLIB.ecl_final_&SNAPSHOT_MONTH.
  group by ifrs9_lbl, pd_tier, fico_band, ltv_band, state_region
  order by ifrs9_lbl, pd_tier, fico_band, ltv_band
  ;
quit;
