#!/usr/bin/env bash
#
# This script runs the survival modeling for tumor-TIL data.
#
# To use the script, make sure that `singularity` or `docker` is available on the
# command line.
#
# Example:
#
#   bash run-v1.sh tumor-output/ tils-output/ survival.csv outputs/
#
# Author: Jakub Kaczmarzyk <jakub.kaczmarzyk@stonybrookmedicine.edu>

set -eu

TILALIGN_VERSION="0.1.0"

usage() {
    cat << EOF
usage: run-v1.sh TUMOR_OUTPUT_DIR TIL_OUTPUT_DIR SURVIVAL_CSV ANALYSIS_OUTPUT_DIR

Learn survival models based on spatial characteristics of tumor and tumor-infiltrating
lymphocytes (TILs). This depends on pre-existing tumor and TIL segmentations, as well
as a CSV with survival information.

The tumor and TIL segmentation outputs are files with the name 'prediction-SLIDE_ID',
where SLIDE_ID is a unique ID for the slide. The rows in the survival CSV must have the
same IDs. Each row should contain the information for one slide.

Survival CSV sample:

slideID,survivalA,censorA.0yes.1no
001,1448,0
002,1474,0
003,4005,1

Report bugs to: Jakub Kaczmarzyk <jakub.kaczmarzyk@stonybrookmedicine.edu>
EOF
}

if [ "$#" -ne 4 ]; then
    echo "Error: script requires four arguments"
    usage
    exit 1
fi

# Get the version as a short git commit (or unknown).
version=$(git describe --always 2> /dev/null || echo unknown)

echo "+ ---------------------------------------------------------- +"
echo "|                                                            |"
echo "|           Federated Tumor/TIL Analysis Pipeline            |"
echo "|                      Version $version                       |"
echo "|                                                            |"
echo "|            Department of Biomedical Informatics            |"
echo "|                   Stony Brook University                   |"
echo "|                                                            |"
echo "| If have questions or encounter errors, please email        |"
echo "| Jakub Kaczmarzyk <jakub.kaczmarzyk@stonybrookmedicine.edu> |"
echo "| and Tahsin Kurc <tkurc@stonybrookmedicine.edu>             |"
echo "|                                                            |"
echo "|        ______                  ___               __        |"
echo "|       / __/ /____  ___ __ __  / _ )_______ ___  / /__      |"
echo "|      _\ \/ __/ _ \/ _ / // / / _  / __/ _ / _ \/  '_/      |"
echo "|     /___/\__/\___/_//_\_, / /____/_/  \___\___/_/\_\       |"
echo "|                      /___/                                 |"
echo "|                                                            |"
echo "+ ---------------------------------------------------------- +"
echo

echo "Timestamp: $(date)"

tumor_output="$(realpath "$1")"
til_output="$(realpath "$2")"
survival_csv="$(realpath "$3")"
analysis_output="$(realpath "$4")"

# Return 0 exit code if the program is found. Non-zero otherwise.
program_exists() {
  hash "$1" 2>/dev/null;
}

# We prefer to use singularity because if it is installed, it is (almost) definitely
# usable. Docker, on the other hand, can be found on the command line but will not be
# usable. For instance, users need to have sudo access to use docker.
echo "Searching for a container runner..."
echo "Checking whether Apptainer/Singularity or Docker is installed..."

container_runner="singularity"
can_use_singularity=false
can_use_docker=false

if program_exists "singularity"; then
    echo "Found Apptainer/Singularity!"
    echo "Checking whether we have the ability to use Apptainer/Singularity..."
    if ( img=$(mktemp --suffix=.sif) \
         && singularity pull --force "$img" 'docker://alpine:3.12' 2> /dev/null > /dev/null \
         && singularity run "$img" true && rm -f "$img" ); then
        echo "We can use Apptainer/Singularity!"
        can_use_singularity=true
    else
        echo "Error: we found singularity/apptainer but we cannot pull and/or run"
        echo "       singularity/apptainer images..."
        echo "Trying Docker next..."
        container_runner="docker"
    fi
else
    echo "Could not find Apptainer/Singularity..."
fi

if [ "$container_runner" = "docker" ]; then
    if program_exists "docker" ; then
        echo "Found Docker!"
        echo "Checking whether we have permission to use Docker..."
        # attempt to use docker. it is potentially not usable because it requires sudo.
        if ! (docker images 2> /dev/null > /dev/null); then
            echo "Error: we found 'docker' but we cannot use it. Please ensure that that"
            echo "       Docker daemon is running and that you have the proper permissions"
            echo "       to use 'docker'."
            exit 3
        fi
        container_runner="docker"
        can_use_docker=true
        echo "We can use Docker!"
    else
        echo "Could not find Docker..."
    fi
fi

if [ "$can_use_docker" != true ] && [ "$can_use_singularity" != true ]; then
    echo "Error: no container runner found!"
    echo "       We cannot run this code without a container runner."
    echo "       We tried to find 'singularity' and 'docker' but neither is available."
    echo "       To fix this, please install Docker or Apptainer/Singularity."
    exit 4
fi

echo "Container runner: $container_runner"

echo "Checking whether the input directories exist..."
if [ ! -d "$tumor_output" ]; then
    echo "Error: tumor output directory not found: $tumor_output"
    exit 5
fi
if [ ! -d "$til_output" ]; then
    echo "Error: TIL output directory not found: $til_output"
    exit 6
fi
echo "Checking whether survival CSV exists..."
if [ ! -f "$survival_csv" ]; then
    echo "Error: survival CSV not found: $survival_csv"
    exit 7
fi

mkdir -p "$analysis_output"

run_pipeline_in_singularity() {
    # Only modify the cachedir if /dev/shm is writable.
    if [ -w "/dev/shm/" ]; then
        SINGULARITY_CACHEDIR="${SINGULARITY_CACHEDIR:-/dev/shm/tumor-til-survival-analysis/}"
        APPTAINER_CACHEDIR=$SINGULARITY_CACHEDIR
        echo "Setting apptainer/singularity cache directory variables..."
        echo "    SINGULARITY_CACHEDIR=$SINGULARITY_CACHEDIR"
        echo "    APPTAINER_CACHEDIR=$APPTAINER_CACHEDIR"
        export SINGULARITY_CACHEDIR
        export APPTAINER_CACHEDIR
    fi
    # Run the TIL-align workflow.
    tilalign_container="tilalign_${TILALIGN_VERSION}.sif"
    echo "Checking whether TIL-align container exists..."
    if [ ! -f "$tilalign_container" ]; then
        echo "Downloading TIL-align container"
        singularity pull docker://kaczmarj/tilalign:$TILALIGN_VERSION
    fi

    echo "Running TIL-align pipeline..."
    singularity exec \
        --bind "$tumor_output:/data/results-tumor:ro" \
        --bind "$til_output:/data/results-tils:ro" \
        --bind "$survival_csv:/data/sample_info.csv:ro" \
        --bind "$analysis_output:/data/results-tilalign:rw" \
        --contain \
        "$tilalign_container" \
            Rscript --vanilla \
                /code/commandLineAlign.R \
                    inceptionv4 \
                    "/data/results-tils" \
                    0.1 \
                    "/data/results-tumor" \
                    0.5 \
                    "" \
                    output.csv \
                    "/data/results-tilalign/" \
                    true \
                    "/data/sample_info.csv"

    echo "Running survival pipeline..."
    # TODO: in singularity, /tmp is cleared if we use --contain. But we need a writable
    # directory, so we copy the rmd into the host /tmp dir then mount /tmp to preserve
    # our writable directory.
    tmpdir=/tmp/rmarkdowndir
    mkdir -p $tmpdir
    singularity exec --bind /tmp:/tmp:rw "$tilalign_container" cp /code/Descriptive_Statistics.rmd "$tmpdir"

    singularity exec \
        --bind "$analysis_output:/data:rw" \
        --bind /tmp:/tmp:rw \
        --contain \
        "$tilalign_container" \
            Rscript --vanilla \
                /code/renderWrapper.R \
                    "/data/output.csv" \
                    "survivalA" \
                    "censorA.0yes.1no" \
                    "pdf_document"
}

run_pipeline_in_docker() {
    # Run the TIL-align workflow.
    tilalign_container="kaczmarj/tilalign:$TILALIGN_VERSION"
    echo "Running TIL-align pipeline..."
    docker run \
        --rm \
        --user "$(id -u)":"$(id -g)" \
        --mount type=bind,source="$tumor_output",destination=/data/results-tumor,readonly \
        --mount type=bind,source="$til_output",destination=/data/results-tils,readonly \
        --mount type=bind,source="$analysis_output",destination=/data/results-tilalign \
        --mount type=bind,source="$survival_csv",destination=/data/sample_info.csv,readonly \
        --entrypoint Rscript \
        "$tilalign_container" \
            --vanilla \
            /code/commandLineAlign.R \
            inceptionv4 \
            "/data/results-tils" \
            0.1 \
            "/data/results-tumor" \
            0.5 \
            "" \
            output.csv \
            "/data/results-tilalign" \
            true \
            "/data/sample_info.csv"

    echo "Running survival pipeline..."
    docker run \
        --rm \
        --user "$(id -u)":"$(id -g)" \
        --mount type=bind,source="$analysis_output",destination=/data/ \
        --entrypoint Rscript \
        "$tilalign_container" \
            --vanilla \
            /code/renderWrapper.R \
            "/data/output.csv" \
            "survivalA" \
            "censorA.0yes.1no" \
            "pdf_document"
}

if [ "$container_runner" = "singularity" ]; then
    run_pipeline_in_singularity
elif [ "$container_runner" = "docker" ]; then
    run_pipeline_in_docker
else
    echo "Error: we seem to have a point in the code we thought we would never reach."
    echo "       Please email Jakub Kaczmarzyk <jakub.kaczmarzyk@stonybrookmedicine.edu>."
    exit 7
fi

echo "Wrote output to $analysis_output"
