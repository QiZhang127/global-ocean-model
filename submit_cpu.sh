#!/bin/bash
#SBATCH --job-name=era5
#SBATCH --account=prio_ey239
#SBATCH --time=24:00:00
#SBATCH --ntasks=1
#SBATCH --partition priority
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
echo "$USER"
#export JULIA_DEPOT_PATH=/home/${USER}/project_pi_ey239/${USER}/julia_depot
export JULIA_DEPOT_PATH=/nfs/roberts/pi/pi_ey239/qi/julia_depot

#----------------------------------------------------------------------
# ROOT: makes writing file paths easier, but is not completely necessary
#----------------------------------------------------------------------

# ROOT=/home/${USER}/project_pi_ey239/${USER}/global-ocean-model

ROOT=/nfs/roberts/pi/pi_ey239/qi/global-ocean-model

[ ! -d $ROOT ] && echo "ERROR: $ROOT directory does not exist"

#----------------------------------------------------------------------
# SIMULATION: Path to simulation file you want to run
# ** Note -> you really shouldn't have to change this
#----------------------------------------------------------------------

#SIMULATION=${ROOT}/utils/download-ecco.jl

SIMULATION=${ROOT}/utils/download-ecco-darwin.jl

# SIMULATION=${ROOT}/utils/download-era5.jl
#SIMULATION=${ROOT}/utils/glorys.jl

# SIMULATION=${ROOT}/main_cpu.jl

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

# source /home/${USER}/.copernicus-env
# test -n "$COPERNICUSMARINE_SERVICE_USERNAME" && echo "username is set"
# test -n "$COPERNICUSMARINE_SERVICE_PASSWORD" && echo "password is set"
#----------------------------------------------------------------------
# SRUN: run the SIMULATION using the specified PROJECT
#----------------------------------------------------------------------

# echo "Instantiating Julia environment..."
# julia --project="${PROJECT}" -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'

# set -e

# echo "Updating ERA5 backend packages..."

# julia --project="${PROJECT}" -e '
# using Pkg
# Pkg.Registry.update()
# Pkg.add(Pkg.PackageSpec(name="NumericalEarth", version="0.6.1"))
# Pkg.add(Pkg.PackageSpec(name="CopernicusClimateDataStore", version="0.2"))
# Pkg.resolve()
# Pkg.precompile()
# '

# echo "Checking ERA5 backend..."

# julia --project="${PROJECT}" -e '
# using NumericalEarth
# using CopernicusClimateDataStore

# extension = Base.get_extension(
#     NumericalEarth,
#     :NumericalEarthCopernicusClimateDataStoreExt
# )

# @assert extension !== nothing "ERA5 download extension did not load"
# println("ERA5 download extension loaded successfully")
# '

# echo "Running ${SIMULATION}..."
julia --project="${PROJECT}" "${SIMULATION}"

