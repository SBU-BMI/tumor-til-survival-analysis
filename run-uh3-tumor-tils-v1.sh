#!/usr/bin/env bash
#
# This script runs the survival modeling for tumor-TIL data.
#
# To use the script, make sure that `singularity` or `docker` is available on the
# command line.
#
# Example:
#
#   bash run-uh3-tumor-tils-v1.sh tumor-output/ tils-output/ outputs/
#
# Author: Jakub Kaczmarzyk <jakub.kaczmarzyk@stonybrookmedicine.edu>

set -e

TILALIGN_VERSION="85d8768cec7945b505557620a3d87dd54cd3e439"

usage="usage: $(basename "$0") TUMOR_OUTPUT_DIR TIL_OUTPUT_DIR ANALYSIS_OUTPUT_DIR"

if [ "$#" -ne 3 ]; then
    echo "Error: script requires three arguments"
    echo "$usage"
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

tumor_output="$(realpath $1)"
til_output="$(realpath $2)"
analysis_output="$(realpath $3)"

set -eu

# Return 0 exit code if the program is found. Non-zero otherwise.
program_exists() {
  hash "$1" 2>/dev/null;
}

# We prefer to use singularity because if it is installed, it is (almost) definitely
# usable. Docker, on the other hand, can be found on the command line but will not be
# usable. For instance, users need to have sudo access to use docker.
echo "Searching for a container runner..."
echo "Checking whether Apptainer/Singularity or Docker is installed..."

if program_exists "singularity2"; then
    container_runner="singularity"
    echo "Found Apptainer/Singularity!"
elif program_exists "docker"; then
    echo "Could not find Apptainer/Singularity..."
    echo "Found Docker!"
    echo "Checking whether we have permission to use Docker..."
    # attempt to use docker. it is potentially not usable because it requires sudo.
    if ! (docker images 2> /dev/null > /dev/null); then
        echo "Error: we found 'docker' but we cannot use it. Please ensure you have"
        echo "       the proper permissions to run docker."
        exit 3
    fi
    container_runner="docker"
    echo "We can use Docker!"
else
    echo "Error: a container runner is not found!"
    echo "       We cannot run this code without a container runner."
    echo "       We tried to find 'singularity' and 'docker' but neither is available."
    echo "       To fix this, please install Docker or Apptainer/Singularity."
    exit 4
fi

echo "Container runner: $container_runner"

echo "Checking whether the input directories exist..."
if [ ! -d "$tumor_output" ]; then
    echo "Error: tumor output directory not found. ${tumor_output}"
    exit 5
fi
if [ ! -d "$til_output" ]; then
    echo "Error: TIL output directory not found. ${til_output}"
    exit 6
fi

mkdir -p "$analysis_output"

run_pipeline_in_singularity() {

    # TODO: what should we set as the CACHEDIR?
    SINGULARITY_CACHEDIR=/dev/shm/$(whoami)/
    APPTAINER_CACHEDIR=$SINGULARITY_CACHEDIR
    export SINGULARITY_CACHEDIR
    export APPTAINER_CACHEDIR

    # Run the TIL-align workflow.
    tilalign_container="tilalign_${TILALIGN_VERSION}.sif"
    if [ ! -f "$tilalign_container" ]; then
        echo "Downloading TIL-align container"
        singularity pull docker://kaczmarj/tilalign:$TILALIGN_VERSION
    fi

    singularity exec \
        --bind "$tumor_output:/data/results-tumor:ro" \
        --bind "$til_output:/data/results-tils:ro" \
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
    | tee -a "$analysis_output/runtime.log"
}

run_pipeline_in_docker() {
    # Run the TIL-align workflow.
    tilalign_container="kaczmarj/tilalign:$TILALIGN_VERSION"
    docker run \
        --mount type=bind,source=$tumor_output,destination=/data/results-tumor,readonly \
        --mount type=bind,source=$til_output,destination=/data/results-tils,readonly \
        --mount type=bind,source=$analysis_output,destination=/data/results-tilalign \
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
    | tee -a "$analysis_output/runtime.log"
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

# echo "Done."
