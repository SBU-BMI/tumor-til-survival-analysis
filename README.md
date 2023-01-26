# Survival analysis of tumor/TILs

This contains the shell scripts used to run survival analysis pipelines based on
tumor/TIL distributions.

- `run-v1.sh` -- Use this if you have existing tumor / TIL detection outputs.
- `run-v2.sh` -- Use this if you do not have existing tumor / TIL detection outputs.

# FAQs

1. I am getting an error "no space left on device" when building a Singularity image.
    - Answer: Set `SINGULARITY_TMPDIR` and `APPTAINER_TMPDIR` to a directory with more
    free space.
