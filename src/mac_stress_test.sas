/*=============================================================================
  File    : macros/mac_stress_test.sas
  Purpose : Apply macroeconomic shock scenarios to PD/LGD/ECL estimates.
            Supports BASE, ADVERSE, and SEVERELY_ADVERSE scenarios per
            Fed DFAST / FHFA stress test frameworks.
  Params  : inds=          input scored dataset
            outds=         output stressed dataset
            scenario=      scenario label (BASE / ADVERSE / SEVERELY_ADVERSE)
            fico_shock=    FICO score decrease (negative = worse credit)
            ltv_shock=     LTV increase (positive = more underwater)
            unemp_pd_mult= PD multiplier for unemployment shock (1.0 = none)
            hpa_pct=       House Price Appreciation % (negative = HPA decline)
=============================================================================*/

%macro stress_test(inds=, outds=,
                   scenario     = BASE,
                   fico_shock   = 0,
                   ltv_shock    = 0,
                   unemp_pd_mult= 1.0,
                   hpa_pct      = 0);

  %put NOTE: [stress_test] Scenario=&scenario. on &inds. → &outds.;

  data &outds.;
    set &inds.;

    scenario_lbl = "&scenario.";

    /* ── Apply shocks to key risk drivers ── */
    fico_stressed = max(&MIN_FICO., fico_clean + (&fico_shock.));
    ltv_stressed  = min(200, ltv_clean + (&ltv_shock.)
                             - (&hpa_pct. / 100 * ltv_clean));
                    /* HPA decline raises LTV; positive hpa_pct = beneficial */

    /* ── Re-score PD under stressed drivers ── */
    logit_pd_stress = -6.50
      + (-0.008 * fico_stressed)
      + (0.020  * ltv_stressed)
      + (0.015  * dti_clean);

    /* Re-add DPD component (unchanged under macro shock) */
    select (dpd_bucket);
      when ('00_Current')    logit_pd_stress = logit_pd_stress + 0.00;
      when ('01_DPD01-29')   logit_pd_stress = logit_pd_stress + 1.20;
      when ('02_DPD30-59')   logit_pd_stress = logit_pd_stress + 2.50;
      when ('03_DPD60-89')   logit_pd_stress = logit_pd_stress + 3.80;
      when ('04_DPD90-119')  logit_pd_stress = logit_pd_stress + 5.20;
      when ('05_DPD120-179') logit_pd_stress = logit_pd_stress + 6.00;
      when ('06_DPD180+')    logit_pd_stress = logit_pd_stress + 7.50;
      otherwise              logit_pd_stress = logit_pd_stress + 0.50;
    end;

    if mod_flag = 'Y' then logit_pd_stress = logit_pd_stress + 0.80;

    pd_stress = min(1, &unemp_pd_mult. / (1 + exp(-logit_pd_stress)));

    /* ── Stressed LGD (HPA decline increases collateral shortfall) ── */
    hpa_lgd_add = max(0, (ltv_stressed - ltv_clean) * 0.005);
    lgd_stress  = min(1, lgd_estimate + hpa_lgd_add);

    /* ── Stressed ECL ── */
    ecl_stress = pd_stress * lgd_stress * ead;

    /* ── Incremental stress lift ── */
    ecl_delta      = ecl_stress - ecl_12mo;
    ecl_delta_pct  = (ecl_delta / nullif(curr_upb, 0)) * 100;

    /* ── Stressed IFRS9 Stage ── */
    if pd_stress >= 0.20 or dpd_count >= &CUTOFF_DPD.
      then stressed_stage = 'S3';
    else if pd_stress >= 0.02 or dpd_count >= 30
      then stressed_stage = 'S2';
    else  stressed_stage = 'S1';

    stage_migration = (stressed_stage ne ifrs9_stage);

    label
      scenario_lbl   = 'Stress Scenario Label'
      fico_stressed  = 'Shocked FICO Score'
      ltv_stressed   = 'Shocked Current LTV'
      pd_stress      = 'Stressed PD'
      lgd_stress     = 'Stressed LGD'
      ecl_stress     = 'Stressed 12-Month ECL'
      ecl_delta      = 'ECL Stress Lift (Absolute)'
      ecl_delta_pct  = 'ECL Stress Lift (% of UPB)'
      stressed_stage = 'Stage Under Stress'
      stage_migration= 'Stage Migration Flag (0/1)'
    ;
    format
      pd_stress lgd_stress        percent8.4
      ecl_stress ecl_delta        dollar16.2
      ecl_delta_pct               8.4
    ;

  run;

%mend stress_test;
