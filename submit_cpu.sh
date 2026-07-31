#!/bin/bash
#SBATCH --job-name=era5
#SBATCH --account=pi_me586
#SBATCH --time=8:00:00
#SBATCH --ntasks=1
#SBATCH --partition day
#SBATCH --cpus-per-task 4
#SBATCH --mem=80G

# 
# NOTE: use --mem instead of --mem-per-cpu
# otherwise get the following error
# srun: fatal: SLURM_MEM_PER_CPU, SLURM_MEM_PER_GPU, and SLURM_MEM_PER_NODE are mutually exclusive.
#

#----------------------------------------------------------------------
# MODULES: loads necssary modules
# ** Note -> b200 gpus require CUDA version >12.8.0
#    for now we have to use h200 gpus with CUDA 12.6.0
#----------------------------------------------------------------------

module purge
module load Julia/1.12.4-linux-x86_64
module load OpenMPI/5.0.3-GCC-13.3.0-CUDA-12.6.0

#----------------------------------------------------------------------
# EXPORTS: these statements are necessary for CUDA-MPI to work properly
# ** Note -> not all of these may be necssary
#----------------------------------------------------------------------

export JULIA_MPI_HAS_CUDA=true
export UCX_WARN_UNUSED_ENV_VARS=n
export UCX_MEMTYPE_CACHE=n
export UCX_TLS=sm,cuda_copy,cuda_ipc,rc
export UCX_RNDV_SCHEME=put_zcopy
export OMPI_MCA_pml=ob1
export OMPI_MCA_btl=self,vader,tcp
export UCX_ERROR_SIGNALS="SIGILL,SIGBUS,SIGFPE"

#----------------------------------------------------------------------
# JULIA_DEPOT_PATH: where all downloaded julia packages will live
# ** Note -> Best to have this in your project_pi_netID directory
#----------------------------------------------------------------------

export JULIA_DEPOT_PATH=/home/${USER}/project_pi_me586/${USER}/julia_depot

#----------------------------------------------------------------------
# ROOT: makes writing file paths easier, but is not completely necessary
#----------------------------------------------------------------------

ROOT=/home/${USER}/project_pi_me586/${USER}/global-ocean-model

[ ! -d $ROOT ] && echo "ERROR: $ROOT directory does not exist"

#----------------------------------------------------------------------
# SIMULATION: Path to simulation file you want to run
# ** Note -> you really shouldn't have to change this
#----------------------------------------------------------------------

#SIMULATION=${ROOT}/utils/download-ecco.jl

SIMULATION=${ROOT}/utils/download-ecco-darwin.jl

#SIMULATION=${ROOT}/utils/download-era5.jl

#SIMULATION=${ROOT}/main_cpu.jl

[ ! -f $SIMULATION ] && echo "ERROR: $SIMULATION file does not exist"

#----------------------------------------------------------------------
# PROJECT: directory where Project.toml lives
# ** Note ->  Do not put Project.toml at end of the path
#----------------------------------------------------------------------

PROJECT=${ROOT}

#----------------------------------------------------------------------
# ECCO credentials: makes julia aware of your ECCO credentials 
# ** Note -> Best practice is to have these credentials be in a 
#            separate file that you source instead of hardcoding
#            export statements, which exposes your username / password
#
# the file with your credentials should only contains these two lines:
#
# export ECCO_USERNAME=your-username
# export ECCO_PASSWORD=your-password
#
# See link below for information on how to obtain ECCO credentials:
# https://github.com/CliMA/ClimaOcean.jl/blob/main/src/DataWrangling/ECCO/README.md
#----------------------------------------------------------------------

source /home/${USER}/.ecco-env 

# copernicus env
# You can sign up for free at: https://data.marine.copernicus.eu/register.
source /home/${USER}/.copernicus-env

#----------------------------------------------------------------------
# SRUN: run the SIMULATION using the specified PROJECT
#----------------------------------------------------------------------

julia --project=${PROJECT} ${SIMULATION}

