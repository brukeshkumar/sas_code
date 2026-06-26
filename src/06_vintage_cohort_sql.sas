/*=============================================================================
  File    : sql/06_vintage_cohort_sql.sas
  Purpose : Vintage cohort performance analysis — tracks delinquency, default,
            and prepayment rates by origination year and loan age band.
            Used by Finance team for book-of-business stratification.
=============================================================================*/

%put NOTE: [06_vintage_cohort_sql] Building vintage cohort performance table.;

proc sql;
  create table OUTLIB.vintage_cohort_perf as
  select
    vintage_yr,
    age_band,
    fico_band,
    ltv_band,
    purpose_lbl,
    occ_lbl,

    count(distinct loan_id)                         as loan_count        format=comma12.,
    sum(curr_upb)                                   as total_upb         format=dollar22.2,
    mean(fico_clean)                                as avg_fico          format=8.1,
    mean(ltv_clean)                                 as avg_ltv           format=8.2,
    mean(dti_clean)                                 as avg_dti           format=8.2,
    mean(orig_rate)                                 as avg_note_rate     format=8.3,
    mean(curr_rate)                                 as avg_curr_rate     format=8.3,

    /* ── Delinquency counts ── */
    sum(case when dpd_count >= 30  then 1 else 0 end)  as cnt_dq30,
    sum(case when dpd_count >= 60  then 1 else 0 end)  as cnt_dq60,
    sum(case when dpd_count >= 90  then 1 else 0 end)  as cnt_dq90,
    sum(case when dpd_count >= 180 then 1 else 0 end)  as cnt_dq180,

    /* ── Delinquency rates ── */
    calculated cnt_dq30  / calculated loan_count * 100  as dq30_rate  format=8.4,
    calculated cnt_dq60  / calculated loan_count * 100  as dq60_rate  format=8.4,
    calculated cnt_dq90  / calculated loan_count * 100  as dq90_rate  format=8.4,
    calculated cnt_dq180 / calculated loan_count * 100  as dq180_rate format=8.4,

    /* ── Credit events ── */
    sum(default_flag)                               as defaults          format=comma10.,
    sum(prepay_flag)                                as prepays           format=comma10.,
    sum(payoff_flag)                                as payoffs           format=comma10.,

    /* ── CDR / CPR ── */
    calculated defaults / calculated loan_count * 100  as cdr_pct      format=8.4,
    calculated prepays  / calculated loan_count * 100  as cpr_pct      format=8.4,

    /* ── High-risk segment flags ── */
    sum(high_dti_flag)                              as high_dti_count,
    sum(mod_flag = 'Y')                             as mod_count,

    /* ── Concentration across whole cohort table ── */
    calculated total_upb /
      sum(sum(curr_upb)) over () * 100              as upb_share_pct    format=8.3

  from OUTLIB.loan_panel
  where vintage_yr between &VINTAGE_START. and &VINTAGE_END.
  group by
    vintage_yr, age_band, fico_band, ltv_band, purpose_lbl, occ_lbl
  order by
    vintage_yr, age_band, fico_band, ltv_band
  ;
quit;

%put NOTE: [06_vintage_cohort_sql] Complete → OUTLIB.vintage_cohort_perf;
