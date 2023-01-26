#!/usr/bin/env bash
#
# This script runs BRCA tumor and TIL detection on a directory of whole slide images.
# After tumor and TIL detection, the TIL-alignment pipeline is run.
#
# To use the script, make sure that `singularity` is available on the command line.
# Then pass the script a directory of slides and a directory in which to store outputs.
# The directory of slides must only contain slides.
#
# Example:
#
#   CUDA_VISIBLE_DEVICES=0 bash run-uh3-brca-tumor-tils.sh path/to/slides/ outputs/
#
# Author: Jakub Kaczmarzyk <jakub.kaczmarzyk@stonybrookmedicine.edu>

set -eu

WSINFER_VERSION="0.3.5"
TILALIGN_VERSION="b5cd826"

WSINFER_NUM_WORKERS="${WSINFER_NUM_WORKERS:-8}"  # Number of worker processes to use for data loading.
WSINFER_BATCH_SIZE="${WSINFER_BATCH_SIZE:-8}"  # Batch size for every model forward pass.

usage="usage: $(basename "$0") SLIDES_DIR OUTPUT_DIR"

if [ "$#" -ne 2 ]; then
    echo "Error: script requires two arguments"
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


if [ -z "$CUDA_VISIBLE_DEVICES" ]; then
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "Warning: CUDA_VISIBLE_DEVICES environment variable is empty. We cannot use"
    echo "         a GPU without this."
    echo "         Please set CUDA_VISIBLE_DEVICES to use a GPU."
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo
fi

slides_dir="$(realpath $1)"
output_dir="$(realpath $2)"

# Return 0 exit code if the program is found. Non-zero otherwise.
program_exists() {
  hash "$1" 2>/dev/null;
}

# We prefer to use singularity because if it is installed, it is (almost) definitely
# usable. Docker, on the other hand, can be found on the command line but will not be
# usable. For instance, users need to have sudo access to use docker.
echo "Searching for a container runner..."
echo "Checking whether Apptainer/Singularity or Docker is installed..."

if program_exists "singularity"; then
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

# Fail if the slides directory does not exist.
if [ ! -d "$slides_dir" ]; then
    echo "Error: slides directory not found. ${slides_dir}"
    exit 5
fi

# Prepare output directories.
tumor_output="${output_dir}/results-tumor"
til_output="${output_dir}/results-tils"
analysis_output="${output_dir}/results-tilalign-survival/"
mkdir -p "$tumor_output" "$til_output" "$analysis_output"

run_pipeline_in_singularity() {
    # We allow the output directory to exist because one might want to re-run the
    # pipeline. The model inference code will skip any outputs that already exist.

    # The default /tmp dir on harrier can be close to full and this will raise an error
    # when building a singularity image. This could be the case on other systems.
    SINGULARITY_CACHEDIR=/dev/shm/$(whoami)/
    APPTAINER_CACHEDIR=$SINGULARITY_CACHEDIR
    export SINGULARITY_CACHEDIR
    export APPTAINER_CACHEDIR

    # Download WSInfer container if it does not exist.
    wsinfer_container="wsinfer_${WSINFER_VERSION}.sif"
    if [ ! -f "$wsinfer_container" ]; then
        echo "Downloading WSInfer container"
        singularity pull docker://kaczmarj/wsinfer:$WSINFER_VERSION
    fi

    # BRCA tumor results.
    # We bind /data10 because our data are symlinked and the actual files are in /data10.
    # TODO: this will have to be changed in the production script.
    singularity run --nv \
        --env TORCH_HOME="" \
        --bind /data10:/data10:ro \
        --bind "$slides_dir:$slides_dir:ro" \
        --bind "$tumor_output:$tumor_output:rw" \
        "$wsinfer_container" run \
            --wsi-dir "$slides_dir" \
            --results-dir "$tumor_output" \
            --model "resnet34" \
            --weights "TCGA-BRCA-v1" \
            --num-workers "$WSINFER_NUM_WORKERS" \
    | tee -a "$tumor_output/runtime.log"

    singularity run --nv \
        --env TORCH_HOME="" \
        --bind /data10:/data10:ro \
        --bind "$slides_dir:$slides_dir:ro" \
        --bind "$til_output:$til_output:rw" \
        "$wsinfer_container" run \
            --wsi-dir "$slides_dir" \
            --results-dir "$til_output" \
            --model "inception_v4nobn" \
            --weights "TCGA-TILs-v1" \
            --num-workers "$WSINFER_NUM_WORKERS" \
    | tee -a "$til_output/runtime.log"


    # Run the TIL-align workflow.
    # Download TIL-align container if it does not exist.
    tilalign_container="tilalign_${TILALIGN_VERSION}.sif"
    if [ ! -f "$tilalign_container" ]; then
        echo "Downloading TIL-align container"
        singularity pull docker://kaczmarj/tilalign:$TILALIGN_VERSION
    fi

    singularity exec \
        --bind "$tumor_output/model-outputs:/data/results-tumor:ro" \
        --bind "$til_output/model-outputs:/data/results-tils:ro" \
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

    # WSInfer pipeline.
    wsinfer_container="kaczmarj/wsinfer:$WSINFER_VERSION"

    # BRCA tumor results.
    # We bind /data10 because our data are symlinked and the actual files are in /data10.
    # TODO: this will have to be changed in the production script.
    # TODO: How to make sure we have GPU access?
    docker run \
        --user=$(id -u):$(id -g) \
        --env TORCH_HOME="" \
        --mount type=bind,source=/data10,destination=/data10,readonly \
        --mount "type=bind,source=$slides_dir,destination=$slides_dir,readonly" \
        --mount "type=bind,source=$tumor_output,destination=$tumor_output" \
        --workdir "$(pwd)" \
        "$wsinfer_container" run \
            --wsi-dir "$slides_dir" \
            --results-dir "$tumor_output" \
            --model "resnet34" \
            --weights "TCGA-BRCA-v1" \
            --num-workers "$WSINFER_NUM_WORKERS" \
    | tee -a "$tumor_output/runtime.log"

    # We bind /data10 because our data are symlinked and the actual files are in /data10.
    # TODO: this will have to be changed in the production script.
    docker run \
        --user=$(id -u):$(id -g) \
        --env TORCH_HOME="" \
        --mount type=bind,source=/data10,destination=/data10,readonly \
        --mount "type=bind,source=$slides_dir,destination=$slides_dir,readonly" \
        --mount "type=bind,source=$til_output,destination=$til_output" \
        --workdir "$(pwd)" \
        "$wsinfer_container" run \
            --wsi-dir "$slides_dir" \
            --results-dir "$til_output" \
            --model "inception_v4nobn" \
            --weights "TCGA-TILs-v1" \
            --num-workers "$WSINFER_NUM_WORKERS" \
    | tee -a "$til_output/runtime.log"

    # Run the TIL-align workflow.
    tilalign_container="kaczmarj/tilalign:$TILALIGN_VERSION"
    docker run \
        --mount type=bind,source=$tumor_output/model-outputs,destination=/data/results-tumor,readonly \
        --mount type=bind,source=$til_output/model-outputs,destination=/data/results-tils,readonly \
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

echo "Container runner: $container_runner"
echo

if [ "$container_runner" = "singularity" ]; then
    run_pipeline_in_singularity
elif [ "$container_runner" = "docker" ]; then
    run_pipeline_in_docker
else
    echo "Error: we seem to have a point in the code we thought we would never reach."
    echo "       Please email Jakub Kaczmarzyk <jakub.kaczmarzyk@stonybrookmedicine.edu>."
    exit 6
fi

echo "Done."
