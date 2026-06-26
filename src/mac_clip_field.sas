/*=============================================================================
  File    : macros/mac_clip_field.sas
  Purpose : Clip a numeric field to [lo, hi] bounds.
            Produces a new variable &newvar.; original preserved.
  Params  : ds=     input/output dataset (in-place)
            var=    source variable to clip
            lo=     lower bound
            hi=     upper bound
            newvar= name of clipped output variable
=============================================================================*/

%macro clip_field(ds=, var=, lo=, hi=, newvar=);

  %if %length(&ds.)=0 or %length(&var.)=0 %then %do;
    %put ERROR: [clip_field] ds= and var= are required.;
    %return;
  %end;

  data &ds.;
    set &ds.;
    if      &var. < &lo. then &newvar. = &lo.;
    else if &var. > &hi. then &newvar. = &hi.;
    else                      &newvar. = &var.;
    label &newvar. = "Clipped &var. [&lo.-&hi.]";
  run;

  %put NOTE: [clip_field] Created &newvar. from &var. clipped to [&lo., &hi.] on &ds..;

%mend clip_field;
