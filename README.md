# Survival analysis of tumor/TILs

This contains the shell scripts used to run survival analysis pipelines based on
tumor/TIL distributions.

- `run-v1.sh` -- Use this if you have existing tumor / TIL detection outputs.
- `run-v2.sh` -- Use this if you do not have existing tumor / TIL detection outputs.

# `run-v1.sh` walkthrough

This script requires the use of `singularity`, `apptainer`, or `docker`. Please ensure
one of these container runners is installed and usable.

## Usage

```
usage: run-v1.sh TUMOR_OUTPUT_DIR TIL_OUTPUT_DIR SURVIVAL_CSV ANALYSIS_OUTPUT_DIR
```

The script `run-v1.sh` expects four positional arguments:

1. the path to a directory with cancer predictions
2. the path to a directory with lymphocyte predictions
3. the path to a CSV file with survival information
4. the path to an output directory to save pipeline outputs

When `run-v1.sh` is called, the cancer and lymphocyte predictions will be aligned.
These data will then be automatically joined to the information provided in `SURVIVAL_CSV`,
and output will be written. The output is then automatically fed into the analytical
portion of the pipeline, and a descriptive statistics document detailing invasion and
survival is generated.

## Example

```bash
bash run-v1.sh path/to/tumor-results path/to/til-results survival.csv outputs
```

At this time, we assume that each patient has only one slide. The slide IDs are assumed
to be the slide filename minus the extension. For example, if a slide is named `ABC001.svs`,
the slide ID is `ABC001`. The files within the tumor and TIL output directories must
have the names `prediction-SLIDE_ID`.

```
path/to/tumor-outputs/
├── prediction-TCGA-EW-A1OY-01Z-00-DX1
├── prediction-TCGA-E9-A1NI-01Z-00-DX1
├── prediction-TCGA-B6-A0I9-01Z-00-DX1
└── prediction-TCGA-B6-A0I8-01Z-00-DX1
```

```
path/to/til-outputs/
├── prediction-TCGA-EW-A1OY-01Z-00-DX1
├── prediction-TCGA-E9-A1NI-01Z-00-DX1
├── prediction-TCGA-B6-A0I9-01Z-00-DX1
└── prediction-TCGA-B6-A0I8-01Z-00-DX1
```

The survival CSV must have the following column names:

- `slideID`
    - The ID of the patient / slide (each patient is assumed to have a single slide).
- `censorA.0yes.1no`
    - If the patient is a deceased, this should be 1. If not, this should be 0. This
    is right-censored data. Not censored means the patient had an event at this timepoint.
- `survivalA`
    - Time of last followup in days. This is either days to death or days to censoring.

This is an example of the survival CSV (using the same slide IDs as above).

|slideID|censorA.0yes.1no|survivalA|
|----|----|----|
|TCGA-EW-A1OY-01Z-00-DX1|0|908|
|TCGA-E9-A1NI-01Z-00-DX1|0|300|
|TCGA-B6-A0I9-01Z-00-DX1|1|362|
|TCGA-B6-A0I8-01Z-00-DX1|1|749|


# FAQs

1. I am getting an error "no space left on device" when building a Singularity image.
    - Answer: Set `SINGULARITY_TMPDIR` and `APPTAINER_TMPDIR` to a directory with more
    free space.
