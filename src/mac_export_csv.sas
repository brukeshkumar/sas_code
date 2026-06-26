/*=============================================================================
  File    : macros/mac_export_csv.sas
  Purpose : Export a SAS dataset to CSV for downstream Python consumption.
  Params  : ds=       SAS dataset to export
            outfile=  filename (no extension) — written to &OUT_PATH.
=============================================================================*/

%macro export_to_csv(ds=, outfile=);

  %put NOTE: [export_to_csv] Exporting &ds. → &OUT_PATH./&outfile..csv;

  proc export data=&ds.
    outfile = "&OUT_PATH./&outfile..csv"
    dbms    = csv
    replace;
  run;

  %put NOTE: [export_to_csv] Done — &OUT_PATH./&outfile..csv;

%mend export_to_csv;
