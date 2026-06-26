/*=============================================================================
  File    : scoring/09_lgd_scoring.sas
  Purpose : Execute LGD scoring. Calls %compute_lgd.
=============================================================================*/
%compute_lgd(
  inds  = OUTLIB.pd_scored_&SNAPSHOT_MONTH.,
  outds = OUTLIB.lgd_scored_&SNAPSHOT_MONTH.
);
