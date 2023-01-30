# Survival analysis of tumor/TILs

This contains the shell scripts used to run survival analysis pipelines based on
tumor/TIL distributions.

- `run-v1.sh` -- Use this if you have existing tumor / TIL detection outputs.
- `run-v2.sh` -- Use this if you do not have existing tumor / TIL detection outputs.

# `run-v1.sh` walkthrough

`run-v1.sh` expects 4 arguments, the path to cancer predictions, the path to lymphocyte predictions, the path to a csv with survival information, and a folder path for outputs. The survival csv should take the format below:

|slideID|censorA.0yes.1no|survivalA|ExtraCol1|etc|
|----|----|----|----|----|
|file1|0|234|entry1|entry1|
|file2|1|122|entry2|entry2|

When `run-v1.sh` is called, the cancer and lymphocyte predictions will be aligned and metrics will be generated. These data will then be automatically joined to the information provided in `sampInfo.csv`, and output will be written. The output is then automatically fed into the analytical portion of the pipeline, and a descriptive statistics document detailing invasion and survival is generated.

A sample call of v1 would be
```
bash run-v1.sh tumor-output/ tils-output/ survival.csv outputs/
```

# FAQs

1. I am getting an error "no space left on device" when building a Singularity image.
    - Answer: Set `SINGULARITY_TMPDIR` and `APPTAINER_TMPDIR` to a directory with more
    free space.
