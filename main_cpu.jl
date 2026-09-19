# =====================================================================
#
# Entry point for a global ocean simulation with realistic bathymetry 
# 
# Closures:
#   -   the "Gent-McWilliams" `IsopycnalSkewSymmetricDiffusivity`.
#
# Forcing:
#   -   ERA5 Reanalysis
#
# Initialization:
#   -   temperature, salinity, sea ice concentration, and sea ice thickness
#       from the ECCO state estimate.
#   -   BGC from ECCO Darwin model
#
# =====================================================================

# initialization of MPI needs to happen at the start of the script

@info "Import necesary modules ..."

using Oceananigans
using NumericalEarth
using OceanBioME

using NumericalEarth.EarthSystemModels.InterfaceComputations
using NumericalEarth.DataWrangling.ERA5: ERA5PrescribedAtmosphere, ERA5PrescribedRadiation, ERA5HourlySingleLevel
using CDSAPI
using Oceananigans.Units
using Oceananigans.DistributedComputations
using OceanBioME.Models.GasExchangeModel: CarbonDioxideConcentration
using Dates
using Printf
using Statistics


# ---------------------------------------------------------------------
# computing architecture
# ---------------------------------------------------------------------

@info "Setup computing architecture ..."

arch = CPU()

# ---------------------------------------------------------------------
# include source files
# ---------------------------------------------------------------------
include("src/Grid.jl")
include("src/Biogeochemistry.jl")
include("src/Forcing.jl")
include("src/Closures.jl")
include("src/Atmosphere.jl")
include("src/Initialization.jl")
include("src/Output.jl")
include("src/Callback.jl")
include("src/Land.jl")

using .GridSetup
using .BiogeochemistrySetup
using .ForcingSetup
using .ClosureSetup
using .AtmosphereSetup
using .Initialization
using .OutputSetup
using .CallbackSetup
using .LandSetup

# dates to run the simulation
# dates = DateTime(2000,1,1):Month(1):DateTime(2005,12,31)
dates = DateTime(2000,1,1):Month(1):DateTime(2006,1,1)

grid = build_grid(arch; Nx=360, Ny=180)

(; biogeochemistry, boundary_conditions, CO₂_flux1, CO₂_flux2) = build_bgc(grid)

forcing = build_alkalinity_forcing(
    grid;
    amplitude = 1.0,      # amplitude of the release
    lon       = 236.5425, # longitude location of release
    lat       = 48.1292,  # latitude location of release
    sigma     = 5.0,      # standard deviation of the patch (in pixels)
    ti        = 366.0,      # day to start release
    tf        = 367.0      # day to end release
)

# ---------------------------------------------------------------------
# Land
# TODO: should land, atmosphere, radiation, ... all other forcings
#       be combined into a PrescribedForcing.jl module?
# ---------------------------------------------------------------------
(; land) = build_land(arch)

# ---------------------------------------------------------------------
# atmosphere
# ---------------------------------------------------------------------
(; atmosphere, radiation) = build_atmosphere(arch, dates)

# ---------------------------------------------------------------------
# ocean simulation
# ---------------------------------------------------------------------
# define tracers
physics_tracers=(:T, :S,)
bgc_tracers = (:NO₃, :NH₄, :P, :Z, :sPOM, :bPOM, :DOM, :DIC1, :DIC2, :Alk1, :Alk2)
tracers = (physics_tracers..., bgc_tracers...)

closure = build_closure()
free_surface       = SplitExplicitFreeSurface(grid; substeps=70)
momentum_advection = WENOVectorInvariant(order=7)
tracer_advection   = WENO(order=7)

ocean = ocean_simulation(
    grid;
    momentum_advection,
    tracer_advection,
    free_surface,
    tracers,
    forcing,
    closure,
    biogeochemistry,
    boundary_conditions
    )

@show ocean.model

initialize_ocean!(ocean, grid, DateTime(2000, 1, 1))

# ---------------------------------------------------------------------
# coupled simulation
# ---------------------------------------------------------------------
coupled_model = OceanOnlyModel(
        ocean;
        atmosphere,
        radiation
    )

simulation = Simulation(
        coupled_model;
        Δt = 20minutes,
        stop_time = 731days
    )

add_progress_callback!(simulation)

configure_output!(ocean, grid)

checkpoint_dir = "/nfs/roberts/pi/pi_ey239/qi/checkpoints/global_ocean_1deg"
mkpath(checkpoint_dir)

simulation.output_writers[:checkpointer] = Checkpointer(
    simulation.model;
    schedule = WallTimeInterval(3hours),
    dir = checkpoint_dir,
    prefix = "global_ocean_1deg_checkpoint",
    cleanup = true,
    verbose = true
)

run!(simulation)
