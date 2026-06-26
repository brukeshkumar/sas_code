/*=============================================================================
  File    : macros/mac_stage_monthly.sas
  Purpose : Stage one monthly SF loan performance snapshot.
            - Merges origination + performance fields
            - Derives current LTV, PTI, flags, bands
            - Applies clip_field and format-based labeling
            - Runs QA proc means
  Params  : snap_month= 6-digit YYYYMM
            src_lib=    source SAS library
            out_lib=    output SAS library
  Calls   : %snap_label, %clip_field
=============================================================================*/

%macro stage_monthly_loan_file(snap_month=, src_lib=, out_lib=);

  %snap_label(&snap_month.);   /* Sets &SNAP_LBL. */

  %put NOTE: [stage_monthly] Starting staging for &snap_month. (&SNAP_LBL.).;

  /* ── Step 1: Load raw performance file ── */
  data work.raw_&snap_month.;
    set &src_lib..sfperf_&snap_month. (
      keep = loan_id seller_name servicer_name
             orig_upb curr_upb orig_rate curr_rate
             orig_term rem_term orig_date maturity_date
             fico_orig ltv_orig cltv_orig dti_ratio
             purpose occupancy prop_type num_units channel
             state zip_code loan_age dpd_count
             zero_bal_code mod_flag harp_flag relief_refi_flag
             monthly_income monthly_payment
             prop_val_orig prop_val_curr
    );

    /* ── Snapshot identifiers ── */
    snap_month  = &snap_month.;
    snap_label  = "&SNAP_LBL.";
    format snap_month 8. snap_label $7.;

    /* ── Current LTV (prefer current AVM, fallback to orig value) ── */
    if prop_val_curr > 0
      then curr_ltv = (curr_upb / prop_val_curr) * 100;
    else if prop_val_orig > 0
      then curr_ltv = (curr_upb / prop_val_orig) * 100;
    else curr_ltv = .;

    /* ── Payment-to-Income ── */
    if monthly_income > 0
      then pti_ratio = (monthly_payment / monthly_income) * 100;
    else pti_ratio = .;

    /* ── Zero-balance derived flags ── */
    select (put(zero_bal_code, $ZBC.));
      when ('Prepaid/Matured')   prepay_flag  = 1;
      when ('Third Party Sale')  default_flag = 1;
      when ('Short Sale')        default_flag = 1;
      when ('REO Disposition')   default_flag = 1;
      otherwise do;
        prepay_flag  = 0;
        default_flag = 0;
      end;
    end;
    payoff_flag = (zero_bal_code = '02');

    /* ── High-risk flags ── */
    high_dti_flag     = (dti_ratio > 43);
    harp_flag_clean   = (harp_flag = 'Y');
    relief_refi_clean = (relief_refi_flag = 'Y');
    low_doc_flag      = (channel in ('B','T') and dti_ratio > 45);

    /* ── Vintage and age ── */
    vintage_yr   = year(orig_date);
    vintage_qtr  = cats(year(orig_date), 'Q', qtr(orig_date));

    /* ── Foreclosure type ── */
    fc_type = put(state, $FC_TYPE.);

    /* ── Region ── */
    state_region = put(state, $STATE_REGION.);

    label
      snap_month    = 'Snapshot Month (YYYYMM)'
      curr_ltv      = 'Current LTV %'
      pti_ratio     = 'Payment-to-Income Ratio'
      prepay_flag   = 'Prepayment Event Flag'
      default_flag  = 'Default Event Flag'
      high_dti_flag = 'DTI > 43 Flag'
      vintage_yr    = 'Origination Vintage Year'
      vintage_qtr   = 'Origination Vintage Quarter'
      fc_type       = 'Foreclosure Type (Judicial/Non)'
      state_region  = 'Geographic Region'
    ;

    format orig_date maturity_date date9.;

  run;

  /* ── Step 2: Clip FICO and LTV ── */
  %clip_field(ds=work.raw_&snap_month., var=fico_orig, lo=&MIN_FICO., hi=&MAX_FICO., newvar=fico_clean);
  %clip_field(ds=work.raw_&snap_month., var=curr_ltv,  lo=0,           hi=200,        newvar=ltv_clean);
  %clip_field(ds=work.raw_&snap_month., var=dti_ratio, lo=0,           hi=100,        newvar=dti_clean);

  /* ── Step 3: Apply format-based band labels ── */
  data &out_lib..staged_&snap_month.;
    set work.raw_&snap_month.;

    fico_band    = put(fico_clean,  FICO_BAND.);
    ltv_band     = put(ltv_clean,   LTV_BAND.);
    dti_band     = put(dti_clean,   DTI_BAND.);
    dpd_bucket   = put(dpd_count,   DPD_BUCKET.);
    age_band     = put(loan_age,    AGE_BAND.);
    purpose_lbl  = put(purpose,     $LOAN_PURPOSE.);
    occ_lbl      = put(occupancy,   $OCC_TYPE.);
    prop_lbl     = put(prop_type,   $PROP_TYPE.);
    channel_lbl  = put(channel,     $CHANNEL.);
    mod_lbl      = put(mod_flag,    $MOD_FLAG.);

  run;

  /* ── Step 4: QA summary ── */
  proc means data=&out_lib..staged_&snap_month.
    n nmiss mean min max stddev maxdec=2;
    var curr_upb fico_clean ltv_clean dti_clean pti_ratio dpd_count loan_age;
    title "QA — Staged Snapshot &SNAP_LBL.";
  run;

  /* ── Step 5: Record count check ── */
  proc sql noprint;
    select count(*) into :_rec_cnt trimmed
    from &out_lib..staged_&snap_month.;
  quit;
  %put NOTE: [stage_monthly] &snap_month. staged with &_rec_cnt. records → &out_lib..staged_&snap_month.;

%mend stage_monthly_loan_file;
