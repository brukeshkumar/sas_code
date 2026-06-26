/*=============================================================================
  File    : sql/05_portfolio_summary_sql.sas
  Purpose : Current-snapshot portfolio summary aggregated by key risk segments.
            Uses PROC SQL with calculated aliases, multi-level grouping,
            and ratio derivations.
=============================================================================*/

%put NOTE: [05_portfolio_summary_sql] Building portfolio summary for &SNAPSHOT_MONTH.;

proc sql;
  create table OUTLIB.portfolio_summary_&SNAPSHOT_MONTH. as
  select
    /* ── Dimensions ── */
    state,
    state_region,
    fico_band,
    ltv_band,
    dti_band,
    dpd_bucket,
    purpose_lbl         as loan_purpose,
    occ_lbl             as occupancy_type,
    prop_lbl            as property_type,
    channel_lbl         as origination_channel,
    age_band,
    vintage_yr,
    fc_type             as foreclosure_type,

    /* ── Volume metrics ── */
    count(distinct loan_id)             as loan_count         format=comma12.,
    sum(curr_upb)                       as total_upb          format=dollar22.2,
    mean(curr_upb)                      as avg_upb            format=dollar16.2,
    sum(orig_upb)                       as total_orig_upb     format=dollar22.2,

    /* ── Credit quality ── */
    mean(fico_clean)                    as avg_fico           format=8.1,
    min(fico_clean)                     as min_fico           format=8.0,
    mean(ltv_clean)                     as avg_curr_ltv       format=8.2,
    mean(dti_clean)                     as avg_dti            format=8.2,
    mean(pti_ratio)                     as avg_pti            format=8.2,
    mean(loan_age)                      as avg_loan_age_mo    format=8.1,

    /* ── Delinquency ── */
    sum(curr_upb * (dpd_count >= 1))    as upb_dq1_plus       format=dollar20.2,
    sum(curr_upb * (dpd_count >= 30))   as upb_dq30_plus      format=dollar20.2,
    sum(curr_upb * (dpd_count >= 60))   as upb_dq60_plus      format=dollar20.2,
    sum(curr_upb * (dpd_count >= 90))   as upb_dq90_plus      format=dollar20.2,
    sum(curr_upb * (dpd_count >= 180))  as upb_dq180_plus     format=dollar20.2,

    /* ── Delinquency rates ── */
    calculated upb_dq30_plus  / calculated total_upb * 100  as dq30_rate_pct  format=8.4,
    calculated upb_dq60_plus  / calculated total_upb * 100  as dq60_rate_pct  format=8.4,
    calculated upb_dq90_plus  / calculated total_upb * 100  as dq90_rate_pct  format=8.4,
    calculated upb_dq180_plus / calculated total_upb * 100  as dq180_rate_pct format=8.4,

    /* ── Event flags ── */
    sum(default_flag)                   as default_count      format=comma10.,
    sum(prepay_flag)                    as prepay_count       format=comma10.,
    sum(curr_upb * default_flag)        as default_upb        format=dollar20.2,
    sum(curr_upb * prepay_flag)         as prepay_upb         format=dollar20.2,
    calculated default_count
      / calculated loan_count * 100     as default_rate_pct   format=8.4,

    /* ── High-risk flags ── */
    sum(high_dti_flag)                  as high_dti_count     format=comma10.,
    sum(low_doc_flag)                   as low_doc_count      format=comma10.,
    sum(mod_flag = 'Y')                 as modified_count     format=comma10.,
    sum(harp_flag_clean)                as harp_count         format=comma10.,

    /* ── Concentration ── */
    calculated loan_count
      / sum(count(distinct loan_id)) over () * 100  as pct_of_total_loans  format=8.2

  from OUTLIB.staged_&SNAPSHOT_MONTH.
  where snap_month = &SNAPSHOT_MONTH.
  group by
    state, state_region, fico_band, ltv_band, dti_band, dpd_bucket,
    purpose_lbl, occ_lbl, prop_lbl, channel_lbl,
    age_band, vintage_yr, fc_type
  order by
    state_region, state, fico_band, ltv_band
  ;
quit;

%put NOTE: [05_portfolio_summary_sql] Complete → OUTLIB.portfolio_summary_&SNAPSHOT_MONTH.;
