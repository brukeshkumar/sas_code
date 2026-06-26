/*=============================================================================
  File    : macros/mac_pd_score.sas
  Purpose : Compute 12-month Probability of Default (PD) score using a
            logistic regression framework. Coefficients are illustrative
            and represent the type of model used in GSE credit analytics.
  Params  : inds=   input dataset (must have fico_clean, ltv_clean, etc.)
            outds=  output dataset with pd_score, logit_pd, pd_tier
=============================================================================*/

%macro compute_pd_score(inds=, outds=);

  %put NOTE: [compute_pd_score] Scoring &inds. → &outds.;

  data &outds.;
    set &inds.;

    /* ── Base intercept (calibrated to ~1% avg PD in performing book) ── */
    logit_pd = -6.50;

    /* ── FICO: inverse relationship ── */
    if fico_clean ne . then
      logit_pd = logit_pd + (-0.008 * fico_clean);

    /* ── Current LTV: positive relationship ── */
    if ltv_clean ne . then
      logit_pd = logit_pd + (0.020 * ltv_clean);

    /* ── DTI: positive relationship ── */
    if dti_clean ne . then
      logit_pd = logit_pd + (0.015 * dti_clean);

    /* ── Loan age: seasoning curve (beneficial early, risk rises late) ── */
    if loan_age ne . then do;
      if loan_age <= 36
        then logit_pd = logit_pd + (-0.010 * loan_age);
      else
        logit_pd = logit_pd + (0.002 * (loan_age - 36));
    end;

    /* ── Delinquency status (dominant driver) ── */
    select (dpd_bucket);
      when ('00_Current')    logit_pd = logit_pd + 0.00;
      when ('01_DPD01-29')   logit_pd = logit_pd + 1.20;
      when ('02_DPD30-59')   logit_pd = logit_pd + 2.50;
      when ('03_DPD60-89')   logit_pd = logit_pd + 3.80;
      when ('04_DPD90-119')  logit_pd = logit_pd + 5.20;
      when ('05_DPD120-179') logit_pd = logit_pd + 6.00;
      when ('06_DPD180+')    logit_pd = logit_pd + 7.50;
      otherwise              logit_pd = logit_pd + 0.50;
    end;

    /* ── Occupancy risk add-on ── */
    select (occupancy);
      when ('P') logit_pd = logit_pd + 0.00;
      when ('S') logit_pd = logit_pd + 0.30;
      when ('I') logit_pd = logit_pd + 0.65;
      otherwise  logit_pd = logit_pd + 0.20;
    end;

    /* ── Loan purpose add-on ── */
    select (purpose);
      when ('P') logit_pd = logit_pd + 0.00;  /* Purchase    */
      when ('N') logit_pd = logit_pd + 0.10;  /* R/T Refi    */
      when ('C') logit_pd = logit_pd + 0.25;  /* Cash-out    */
      otherwise  logit_pd = logit_pd + 0.15;
    end;

    /* ── Origination channel add-on ── */
    select (channel);
      when ('R') logit_pd = logit_pd + 0.00;
      when ('C') logit_pd = logit_pd + 0.05;
      when ('B') logit_pd = logit_pd + 0.15;
      when ('T') logit_pd = logit_pd + 0.20;
      otherwise  logit_pd = logit_pd + 0.10;
    end;

    /* ── Modification overlay ── */
    if mod_flag = 'Y' then logit_pd = logit_pd + 0.80;

    /* ── HARP / Relief Refi benefit ── */
    if harp_flag_clean = 1 then logit_pd = logit_pd - 0.15;

    /* ── Convert log-odds to probability ── */
    pd_score = 1 / (1 + exp(-logit_pd));
    pd_score = min(pd_score, 1);   /* Cap at 100% */

    /* ── PD Tier Assignment ── */
    if      pd_score <  0.005 then pd_tier = '1_Very Low (<0.5%)';
    else if pd_score <  0.020 then pd_tier = '2_Low (0.5-2%)';
    else if pd_score <  0.050 then pd_tier = '3_Moderate (2-5%)';
    else if pd_score <  0.100 then pd_tier = '4_Elevated (5-10%)';
    else if pd_score <  0.200 then pd_tier = '5_High (10-20%)';
    else                           pd_tier = '6_Very High (20%+)';

    label
      logit_pd = 'Log-Odds of Default'
      pd_score = '12-Month Probability of Default'
      pd_tier  = 'PD Risk Tier'
    ;
    format pd_score percent8.4;

  run;

  proc means data=&outds. n mean min max stddev maxdec=4;
    var pd_score logit_pd;
    title "PD Score Distribution — &outds.";
  run;

%mend compute_pd_score;
