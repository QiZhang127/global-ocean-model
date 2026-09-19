module OutputSetup

using Oceananigans: JLD2Writer, TimeInterval
using Oceananigans.Units: days
using Oceananigans.Architectures: architecture
using Oceananigans.DistributedComputations: Distributed
using Oceananigans.Models: BoundaryConditionOperation
using MPI
using OceanBioME: chlorophyll

export configure_output!

# Change RUN_NAME for a new set of output files.
const RUN_NAME = "ice_glorys01_2_iron_3"
const OUTPUT_DIRECTORY = normpath(joinpath(@__DIR__, "..", "output_ice"))
const OUTPUT_INTERVAL = 1days

function global_count(local_count, grid)
    arch = architecture(grid)
    return arch isa Distributed ?
           MPI.Allreduce(local_count, +, arch.communicator) : local_count
end

# Daily snapshots of surface fields, free surface, and sea ice.
function configure_output!(ocean, grid)
    # sea_ice is created in main.jl before this call.
    owner = parentmodule(@__MODULE__)
    isdefined(owner, :sea_ice) || error(
        "Create a module-level sea_ice in main.jl before " *
        "calling configure_output!(ocean, grid)."
    )
    sea_ice = getfield(owner, :sea_ice)

    ocean.model.grid === grid || error("grid is not the ocean model grid.")
    sea_ice.model.grid === grid || error("Ocean and sea ice must share grid.")

    # Check writer registrations across all ranks.
    duplicate_keys = Int(haskey(ocean.output_writers, :surface_jld2)) +
                     Int(haskey(ocean.output_writers, :free_surface)) +
                     Int(haskey(sea_ice.output_writers, :surface))
    global_count(duplicate_keys, grid) == 0 || error(
        "Output writers already configured. Call configure_output! only once."
    )

    # Fluxes already include the ice limitation from Biogeochemistry.jl.
    flux1 = BoundaryConditionOperation(ocean.model.tracers.DIC1, :top, ocean.model)
    flux2 = BoundaryConditionOperation(ocean.model.tracers.DIC2, :top, ocean.model)
    chl = chlorophyll(ocean.model.biogeochemistry, ocean.model)
    ocean_outputs = merge(ocean.model.tracers,
                          ocean.model.velocities,
                          (; flux1, flux2, chl))

    surface_writer = JLD2Writer(
        ocean.model, ocean_outputs;
        schedule = TimeInterval(OUTPUT_INTERVAL),
        dir = OUTPUT_DIRECTORY,
        filename = "surface_fields_$(RUN_NAME)",
        indices = (:, :, grid.Nz),
        with_halos = true,
        overwrite_existing = true,
    )

    free_surface_writer = JLD2Writer(
        ocean.model, (; η = ocean.model.free_surface.displacement);
        schedule = TimeInterval(OUTPUT_INTERVAL),
        dir = OUTPUT_DIRECTORY,
        filename = "free_surface_$(RUN_NAME)",
        with_halos = true,
        overwrite_existing = true,
    )

    ice_outputs = (
        h = sea_ice.model.ice_thickness,
        ice_concentration = sea_ice.model.ice_concentration,
    )
    ice_writer = JLD2Writer(
        sea_ice.model, ice_outputs;
        schedule = TimeInterval(OUTPUT_INTERVAL),
        dir = OUTPUT_DIRECTORY,
        filename = "sea_ice_$(RUN_NAME)",
        with_halos = true,
        overwrite_existing = true,
    )

    ocean.output_writers[:surface_jld2] = surface_writer
    ocean.output_writers[:free_surface] = free_surface_writer
    sea_ice.output_writers[:surface] = ice_writer

    return nothing
end

end
