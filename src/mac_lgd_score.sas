/*=============================================================================
  File    : macros/mac_lgd_score.sas
  Purpose : Estimate Loss Given Default (LGD) based on collateral coverage,
            property type, state foreclosure timeline, and modification status.
  Params  : inds=   input dataset
            outds=  output dataset with lgd_estimate, base_lgd, fc_adj, etc.
=============================================================================*/

%macro compute_lgd(inds=, outds=);

  %put NOTE: [compute_lgd] Scoring &inds. → &outds.;

  data &outds.;
    set &inds.;

    /* ── Base LGD driven by Current LTV ── */
    if      ltv_clean <=  60 then base_lgd = 0.10;
    else if ltv_clean <=  75 then base_lgd = 0.18;
    else if ltv_clean <=  80 then base_lgd = 0.22;
    else if ltv_clean <=  90 then base_lgd = 0.30;
    else if ltv_clean <=  97 then base_lgd = 0.38;
    else if ltv_clean ne  .  then base_lgd = 0.48;
    else                          base_lgd = 0.35;  /* Default if LTV missing */

    /* ── Foreclosure timeline adjustment ── */
    fc_type = put(state, $FC_TYPE.);
    if fc_type = 'Judicial'
      then fc_adj = 0.05;    /* Longer timeline → higher carrying costs */
    else  fc_adj = 0.00;

    /* ── Property type adjustment ── */
    select (prop_type);
      when ('SF') prop_adj = 0.00;
      when ('CO') prop_adj = 0.03;
      when ('PU') prop_adj = 0.02;
      when ('MH') prop_adj = 0.08;   /* Manufactured housing — thin resale market */
      when ('2F') prop_adj = 0.04;
      otherwise   prop_adj = 0.05;
    end;

    /* ── Occupancy adjustment ── */
    select (occupancy);
      when ('P') occ_adj = 0.00;
      when ('S') occ_adj = 0.02;
      when ('I') occ_adj = 0.05;   /* Investor — faster deterioration */
      otherwise  occ_adj = 0.02;
    end;

    /* ── Modification benefit (higher recovery rate post-mod) ── */
    if mod_flag = 'Y' then mod_adj = -0.03;
    else                   mod_adj =  0.00;

    /* ── HARP benefit (LTV capped at origination, better-covered) ── */
    if harp_flag_clean = 1 then harp_adj = -0.02;
    else                        harp_adj =  0.00;

    /* ── Final LGD (bounded [0, 1]) ── */
    lgd_estimate = max(0, min(1,
      base_lgd + fc_adj + prop_adj + occ_adj + mod_adj + harp_adj
    ));

    label
      base_lgd     = 'Base LGD from LTV'
      fc_adj       = 'Foreclosure Timeline Adjustment'
      prop_adj     = 'Property Type Adjustment'
      occ_adj      = 'Occupancy Type Adjustment'
      mod_adj      = 'Modification Adjustment'
      harp_adj     = 'HARP Adjustment'
      lgd_estimate = 'Final LGD Estimate'
    ;
    format base_lgd fc_adj prop_adj occ_adj mod_adj harp_adj lgd_estimate percent8.4;

  run;

  proc means data=&outds. n mean min max stddev maxdec=4;
    var lgd_estimate base_lgd;
    title "LGD Distribution — &outds.";
  run;

%mend compute_lgd;
