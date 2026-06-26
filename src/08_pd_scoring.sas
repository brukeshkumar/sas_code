/*=============================================================================
  File    : scoring/08_pd_scoring.sas
  Purpose : Execute PD scoring on current snapshot. Calls %compute_pd_score.
=============================================================================*/
%compute_pd_score(
  inds  = OUTLIB.staged_&SNAPSHOT_MONTH.,
  outds = OUTLIB.pd_scored_&SNAPSHOT_MONTH.
);
