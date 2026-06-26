/*=============================================================================
  File    : sql/07_roll_rate_matrix_sql.sas
  Purpose : Month-over-month DPD bucket transition (roll rate) matrix.
            Uses self-join with correlated subquery to pair consecutive snapshots.
            Also produces a stacked time-series roll rate via macro loop.
=============================================================================*/

%put NOTE: [07_roll_rate_matrix_sql] Building roll rate matrix.;

/* ── Static roll rate: latest two snapshots ── */
proc sql noprint;
  select distinct snap_month into :all_snaps separated by ' '
  from OUTLIB.loan_panel
  order by snap_month;
quit;

%let n_all = %sysfunc(countw(&all_snaps.));
%let prev_snap = %scan(&all_snaps., %eval(&n_all. - 1));
%let curr_snap = %scan(&all_snaps., &n_all.);

%put NOTE: Comparing &prev_snap. → &curr_snap.;

proc sql;
  create table OUTLIB.roll_rate_latest as
  select
    a.dpd_bucket                     as dpd_from        label='DPD Bucket (T)',
    b.dpd_bucket                     as dpd_to          label='DPD Bucket (T+1)',
    "&prev_snap.->  &curr_snap."     as period          label='Transition Period',
    count(distinct a.loan_id)        as loan_count      format=comma10.,
    sum(a.curr_upb)                  as upb_start       format=dollar20.2,
    sum(b.curr_upb)                  as upb_end         format=dollar20.2,

    /* Roll rate = % of loans in each FROM bucket that moved to each TO bucket */
    count(distinct a.loan_id) /
      sum(count(distinct a.loan_id))
        over (partition by a.dpd_bucket) * 100   as roll_rate_pct   format=8.2,

    /* Cure rate = moved to lower DPD */
    case when b.dpd_count < a.dpd_count then 1 else 0 end
                                     as cured_flag      label='Cured Flag',
    sum(case when b.dpd_count < a.dpd_count then 1 else 0 end) /
      count(*) * 100                 as cure_rate_pct   format=8.2

  from OUTLIB.loan_panel a
  inner join OUTLIB.loan_panel b
    on  a.loan_id    = b.loan_id
    and a.snap_month = &prev_snap.
    and b.snap_month = &curr_snap.
  group by a.dpd_bucket, b.dpd_bucket
  order by a.dpd_bucket, b.dpd_bucket
  ;
quit;


/* ── Time-series roll rates (all consecutive pairs) ── */
%macro build_ts_roll_rates(snap_list=);
  %local n i t0 t1;
  %let n = %sysfunc(countw(&snap_list.));

  %do i = 1 %to %eval(&n. - 1);
    %let t0 = %scan(&snap_list., &i.);
    %let t1 = %scan(&snap_list., %eval(&i. + 1));

    proc sql;
      create table work.roll_&t0._&t1. as
      select
        a.dpd_bucket                                   as dpd_from,
        b.dpd_bucket                                   as dpd_to,
        "&t0.->  &t1."                                 as period,
        count(distinct a.loan_id)                      as loan_count,
        sum(b.curr_upb)                                as upb_end        format=dollar20.2,
        count(*) /
          sum(count(*)) over (partition by a.dpd_bucket) * 100
                                                       as roll_rate_pct  format=8.2
      from OUTLIB.loan_panel a
      inner join OUTLIB.loan_panel b
        on  a.loan_id    = b.loan_id
        and a.snap_month = &t0.
        and b.snap_month = &t1.
      group by a.dpd_bucket, b.dpd_bucket
      order by a.dpd_bucket, b.dpd_bucket
      ;
    quit;
  %end;

  /* Stack all periods */
  data OUTLIB.roll_rate_timeseries;
    set work.roll_: ;
  run;

%mend build_ts_roll_rates;

%build_ts_roll_rates(snap_list=&all_snaps.);

%put NOTE: [07_roll_rate_matrix_sql] Complete → OUTLIB.roll_rate_latest + OUTLIB.roll_rate_timeseries;
