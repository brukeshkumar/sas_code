/*=============================================================================
  File    : macros/mac_ecl_compute.sas
  Purpose : Compute 12-month and lifetime Expected Credit Loss (ECL).
            Assigns IFRS 9 / CECL staging classification.
  Params  : inds=   input dataset (must have pd_score, lgd_estimate, curr_upb)
            outds=  output with ecl_12mo, ecl_lifetime, ifrs9_stage
=============================================================================*/

%macro compute_ecl(inds=, outds=);

  %put NOTE: [compute_ecl] Computing ECL: &inds. → &outds.;

  data &outds.;
    set &inds.;

    /* ── EAD: Exposure at Default = Current UPB ── */
    ead = curr_upb;

    /* ── 12-Month ECL ── */
    ecl_12mo = pd_score * lgd_estimate * ead;

    /* ── Cumulative PD over remaining life (geometric survival) ── */
    rem_life_yrs = max(0, rem_term / 12);

    if pd_score < 1 and rem_life_yrs > 0
      then cum_pd = 1 - (1 - pd_score) ** rem_life_yrs;
    else if pd_score >= 1
      then cum_pd = 1;
    else  cum_pd = pd_score;

    /* ── Lifetime ECL with discounting ── */
    if &ECL_DISC_RATE. > 0 and rem_life_yrs > 0 then do;
      discount_factor = (1 - (1 + &ECL_DISC_RATE.) ** (-rem_life_yrs))
                        / &ECL_DISC_RATE.;
      ecl_lifetime = cum_pd * lgd_estimate * ead
                     * discount_factor / rem_life_yrs;
    end;
    else ecl_lifetime = cum_pd * lgd_estimate * ead;

    /* ── IFRS 9 / CECL Stage Classification ── */
    if dpd_count = 0 and pd_score < 0.02 then do;
      ifrs9_stage = 'S1';
      ecl_allowance = ecl_12mo;      /* Stage 1: 12-month ECL */
    end;
    else if dpd_count < &CUTOFF_DPD. or pd_score < 0.20 then do;
      ifrs9_stage = 'S2';
      ecl_allowance = ecl_lifetime;  /* Stage 2: Lifetime ECL */
    end;
    else do;
      ifrs9_stage = 'S3';
      ecl_allowance = ecl_lifetime;  /* Stage 3: Lifetime ECL */
    end;

    ifrs9_lbl = put(ifrs9_stage, $IFRS9.);

    /* ── ECL Coverage Ratio ── */
    if curr_upb > 0
      then ecl_coverage_pct = ecl_allowance / curr_upb * 100;
    else  ecl_coverage_pct = .;

    label
      ead              = 'Exposure at Default (Current UPB)'
      ecl_12mo         = '12-Month ECL'
      ecl_lifetime     = 'Lifetime ECL (Discounted)'
      cum_pd           = 'Cumulative PD over Remaining Life'
      discount_factor  = 'Annuity Discount Factor'
      ecl_allowance    = 'Allowance for Credit Loss (ACL)'
      ifrs9_stage      = 'IFRS9 Stage Code'
      ifrs9_lbl        = 'IFRS9 Stage Label'
      ecl_coverage_pct = 'ECL as % of UPB'
    ;
    format
      ead ecl_12mo ecl_lifetime ecl_allowance  dollar18.2
      pd_score cum_pd lgd_estimate              percent8.4
      ecl_coverage_pct                          8.4
    ;

  run;

  /* Quick ECL summary by stage */
  proc tabulate data=&outds. missing;
    class ifrs9_lbl;
    var curr_upb ecl_allowance ecl_coverage_pct pd_score lgd_estimate;
    table ifrs9_lbl,
          curr_upb    * (sum*f=dollar20. n*f=comma10.)
          ecl_allowance * sum*f=dollar18.
          ecl_coverage_pct * mean*f=8.2
          pd_score * mean*f=percent8.4
          lgd_estimate * mean*f=percent8.4;
    title "ECL Summary by IFRS9 Stage — &outds.";
  run;

%mend compute_ecl;
