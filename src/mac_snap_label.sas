/*=============================================================================
  File    : macros/mac_snap_label.sas
  Purpose : Derive a YYYY-MM display label from a YYYYMM integer snapshot key.
            Sets global macro variable SNAP_LBL.
  Params  : yyyymm — 6-digit snapshot month integer (e.g. 202403)
  Output  : &SNAP_LBL. = '2024-03'
=============================================================================*/

%macro snap_label(yyyymm);

  %global SNAP_LBL;

  %if %length(&yyyymm.) ne 6 %then %do;
    %put ERROR: [snap_label] Expected 6-digit YYYYMM, got: &yyyymm.;
    %let SNAP_LBL = INVALID;
    %return;
  %end;

  %let _yr = %substr(&yyyymm., 1, 4);
  %let _mo = %substr(&yyyymm., 5, 2);
  %let SNAP_LBL = &_yr.-&_mo.;

  %put NOTE: [snap_label] &yyyymm. resolved to &SNAP_LBL.;

%mend snap_label;
