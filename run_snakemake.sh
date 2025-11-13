#!/bin/bash

set -e
set -u

# Help message
usage() {
    echo "Usage: $0 -s <step> -f <config> [-d <dry-run>] [-c <cores>] [-u <unlock>] [-h]"
    echo "Options:"
    echo "  -s  Step to run (required): submit_initial_input, submit_fix_strands, or filter_info_and_vcf_files"
    echo "  -f  Path to config file"
    echo "  -d  Run snakemake --dry-run"
    echo "  -c  Number of cores to use (default: 6)"
    echo "  -u  Unlock snakemake"
    echo "  -h  Show this help message"
    exit 1
}

# Run help message if no args given
if [ "$#" -eq 0 ]; then
    usage
fi

# Default args
dry_run=0
n_cores=6
unlock=0

# Parse args
while getopts "s:f:c:duh" opt; do
  case $opt in
    s) step="$OPTARG" ;;
    f) config="$OPTARG" ;;
    d) dry_run=1 ;;
    c) n_cores="$OPTARG" ;;
    u) unlock=1 ;;
    h) usage ;;
    \?) usage ;;
  esac
done

# Set dry-run flag
if [ "$dry_run" -eq 1 ]; then
    dry_flag="--dry-run"
else
    dry_flag=""
fi

# Set unlock flag
if [ "$unlock" -eq 1 ]; then
    unlock_flag="--unlock"
else
    unlock_flag=""
fi

# Get info about config file path passed in
config_name=$(basename "$config")
config_path=$(dirname "$config")

# Get values set in config file
    # Note that grep only works on simple, single-level .yml file. Using "yq"
    # would be better, but requires tool to be available outside of container
plink_prefix=$(sed 's/#.*//' "$config" | grep "^plink_prefix:" | cut -d':' -f2 | tr -d ' "')
plink_dir=$(dirname "$plink_prefix")

id_list_hwe=$(sed 's/#.*//' "$config" | grep "^id_list_hwe:" | cut -d':' -f2 | tr -d ' "')
id_list_hwe_dir=$(dirname "$id_list_hwe")

out_dir=$(sed 's/#.*//' "$config" | grep "^out_dir:" | cut -d':' -f2 | tr -d ' "')
repo=$(sed 's/#.*//' "$config" | grep "^repo:" | cut -d':' -f2 | tr -d ' "')
use_cont=$(sed 's/#.*//' "$config" | grep "^use_cont:" | cut -d':' -f2 | tr -d ' "')

# Get container paths set in config file - should not change
plink_dir_cont=$(sed 's/#.*//' "$config" | grep "^plink_dir_cont:" | cut -d':' -f2 | tr -d ' "')
id_list_hwe_dir_cont=$(sed 's/#.*//' "$config" | grep "^id_list_hwe_dir_cont:" | cut -d':' -f2 | tr -d ' "')
out_dir_cont=$(sed 's/#.*//' "$config" | grep "^out_dir_cont:" | cut -d':' -f2 | tr -d ' "')
repo_cont=$(sed 's/#.*//' "$config" | grep "^repo_cont:" | cut -d':' -f2 | tr -d ' "')

if [ "$use_cont" = "false" ]; then
    # Run snakemake on local machine using provided conda environment
    snakemake --rerun-triggers mtime --snakefile ${repo}/Snakefile \
        --configfile ${config_path}/${config_name} \
        --cores "$n_cores" "$step" $dry_flag $unlock_flag
elif [ "$use_cont" = "true" ]; then
    # Run snakemake in container (default)
    apptainer exec \
        --writable-tmpfs \
        --bind "${repo}:${repo_cont}" \
        --bind "${plink_dir}:${plink_dir_cont}" \
        --bind "${id_list_hwe_dir}:${id_list_hwe_dir_cont}" \
        --bind "${config_path}:/proj_repo" \
        --bind "${out_dir}:${out_dir_cont}" \
        ${repo}/envs/env_imputation.sif \
        snakemake --rerun-triggers mtime --snakefile ${repo}/Snakefile \
            --configfile /proj_repo/${config_name} \
            --cores "$n_cores" "$step" $dry_flag $unlock_flag

else
    echo "Config file use_cont must be either true or false"
    exit
fi
