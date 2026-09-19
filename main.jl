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
#       from GLORYS
#   -   BGC from ECCO Darwin model
#
# =====================================================================

# initialization of MPI needs to happen at the start of the script
using MPI
MPI.Init()

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
using CUDA
using CUDA: @allowscalar, device!

using Oceananigans: Clock
using NumericalEarth: PrescribedRadiation
using Oceananigans.Simulations: Callback
using Oceananigans.Utils: TimeInterval
using Oceananigans.Units: hour

# Allow scalar indexing during setup.
CUDA.allowscalar(true)

# ---------------------------------------------------------------------
# computing architecture
# ---------------------------------------------------------------------

@info "Setup computing architecture ..."

comm = MPI.COMM_WORLD
rank = MPI.Comm_rank(comm)

arch = Distributed(
    GPU();
    partition = Partition(y = DistributedComputations.Equal()),
    synchronized_communication = true
)

@info CUDA.device(), rank
@info arch

# ---------------------------------------------------------------------
# include source files
# ---------------------------------------------------------------------
include("src/Grid.jl")
include("src/Biogeochemistry_Ice_iron.jl")
include("src/Forcing.jl")
include("src/Closures_iron.jl")
include("src/Atmosphere.jl")
include("src/Initialization_Ice_iron.jl")
include("src/Output_Ice_iron.jl")
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
dates = DateTime(2000,1,1):Month(1):DateTime(2002,01,01)

grid = build_grid(arch)

# ---------------------------------------------------------------------
# Land
# ---------------------------------------------------------------------
(; land) = build_land(arch)

# ---------------------------------------------------------------------
# atmosphere
# ---------------------------------------------------------------------
(; atmosphere, radiation) = build_atmosphere(arch, dates)

(; biogeochemistry, boundary_conditions, CO₂_flux1, CO₂_flux2, ice_bgc_links) = build_bgc(grid, atmosphere)

forcing = build_alkalinity_forcing(
    grid;
    amplitude = 1.0,      # amplitude of the release
    lon       = 236.5425, # longitude location of release
    lat       = 48.1292,  # latitude location of release
    sigma     = 5.0,      # standard deviation of the patch (in pixels)
    ti        = 366.0,    # day to start release
    tf        = 367.0     # day to end release
)

# ---------------------------------------------------------------------
# ocean simulation
# ---------------------------------------------------------------------
# define tracers
physics_tracers=(:T, :S,)
bgc_tracers = (:NO₃, :NH₄, :Fe, :PO₄, :O₂, :P, :Z, :sPOM, :bPOM, :DOM, :DIC1, :DIC2, :Alk1, :Alk2)
tracers = (physics_tracers..., bgc_tracers...)

closure = build_closure()

momentum_advection = WENOVectorInvariant(order=7)

using Oceananigans.Advection: WENO, UpwindBiased

regular_weno = WENO(order=7)
positive_upwind = UpwindBiased(order=1)

tracer_advection = (
    T = regular_weno,
    S = regular_weno,

    NO₃  = positive_upwind,
    NH₄  = positive_upwind,
    Fe   = positive_upwind,
    PO₄  = positive_upwind,
    O₂   = positive_upwind,
    P    = positive_upwind,
    Z    = positive_upwind,
    sPOM = positive_upwind,
    bPOM = positive_upwind,
    DOM  = positive_upwind,

    DIC1 = positive_upwind,
    DIC2 = positive_upwind,
    Alk1 = positive_upwind,
    Alk2 = positive_upwind,
)

ocean = ocean_simulation(
    grid;
    momentum_advection,
    tracer_advection,
    tracers,
    forcing,
    closure,
    biogeochemistry,
    boundary_conditions
    )

initialize_ocean!(ocean, grid, first(dates))

sea_ice = sea_ice_simulation(
    grid, ocean;
    advection = nothing,
    dynamics = nothing,
    snow_thermodynamics = nothing,
)

glorys_dir =
    "/nfs/roberts/pi/pi_ey239/qi/julia_depot/scratchspaces/" *
    "904d977b-046a-4731-8b86-9235c0d1ef02/GLORYS"

initialize_sea_ice!(
    sea_ice, first(dates);
    glorys_dir,
    comm,
)

# Ice concentration for gas exchange.
ice_bgc_links.ice.data =
    sea_ice.model.ice_concentration.data

# ---------------------------------------------------------------------
# coupled simulation
# ---------------------------------------------------------------------
coupled_model = OceanSeaIceModel(
    ocean,
    sea_ice;
    atmosphere,
    radiation,
)

# Check the exchange grid.
@assert coupled_model.interfaces.exchanger.grid == ocean.model.grid

# Ocean shortwave for PAR.
ice_bgc_links.shortwave.data =
    coupled_model.radiation.interface_fluxes.ocean.downwelling_shortwave.data

# Update radiation and biological light.
Oceananigans.TimeSteppers.update_state!(coupled_model)
Oceananigans.TimeSteppers.update_state!(ocean.model)

# Two years, including leap year 2000.
simulation = Simulation(
    coupled_model;
    Δt = 20minutes,
    stop_time = 731days,
)

add_progress_callback!(simulation)

configure_output!(ocean, grid)

# ---------------------------------------------------------------------
# checkpoints
# ---------------------------------------------------------------------
checkpoint_dir =
    "/nfs/roberts/pi/pi_ey239/qi/checkpoints/global_ocean_1deg_iron_resume9821"

mkpath(checkpoint_dir)

simulation.output_writers[:checkpointer] = Checkpointer(
    simulation.model;
    schedule = WallTimeInterval(1hour),
    dir = checkpoint_dir,
    prefix = "global_ocean_1deg_iron_checkpoint",
    cleanup = true,
    verbose = true,
)

restart_iteration = "29765"  # "" to start from day 0.
if isempty(restart_iteration)
    @info "Starting a clean simulation from day 0."
else
    iteration = parse(Int, restart_iteration)
    set!(simulation; iteration)

    @info "Restarted simulation" iteration day =
        ocean.model.clock.time / 86400

    @assert isapprox(
        atmosphere.clock.time,
        ocean.model.clock.time;
        atol = 1,
    )

    @assert isapprox(
        radiation.clock.time,
        ocean.model.clock.time;
        atol = 1,
    )
end

# Check BGC tracers once per model day.
function stop_on_nonfinite_bgc!(simulation)
    clock = ocean.model.clock
    rank = get(ENV, "SLURM_PROCID", "unknown")
    found_nonfinite = false

    for name in bgc_tracers
        data = interior(getproperty(ocean.model.tracers, name))
        any(x -> !isfinite(x), data) || continue
        values = Array(data)
        count_bad = count(x -> !isfinite(x), values)

        if count_bad > 0
            bad_index = findfirst(x -> !isfinite(x), values)

            @error(
                "Nonfinite BGC tracer detected",
                rank,
                tracer = name,
                index = Tuple(bad_index),
                value = values[bad_index],
                count = count_bad,
                day = clock.time / 86400,
                iteration = clock.iteration,
            )

            found_nonfinite = true
        end
    end

    if found_nonfinite
        error("Stopping after checking all BGC tracers.")
    end

    return nothing
end

simulation.callbacks[:bgc_nonfinite_guard] =
    Callback(stop_on_nonfinite_bgc!, IterationInterval(72))

new_checkpoint_dir =
    "/nfs/roberts/pi/pi_ey239/qi/checkpoints/global_ocean_1deg_iron_resume29765"

mkpath(new_checkpoint_dir)

simulation.output_writers[:checkpointer].dir = new_checkpoint_dir

run!(simulation; checkpoint_at_end = true)
