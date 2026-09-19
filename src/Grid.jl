module GridSetup

using Oceananigans: ExponentialDiscretization, TripolarGrid, ImmersedBoundaryGrid
using Oceananigans.Units: meters
using Oceananigans.ImmersedBoundaries: GridFittedBottom
using NumericalEarth: regrid_bathymetry

export build_grid

function build_grid(arch; Nx=360, Ny=180, Nz=50) #Nx=1440, Ny=720, Nz=50

    # total depth of the ocean
    depth = 5000meters

    z = ExponentialDiscretization(
        Nz,
        -depth,
        0;
        scale = depth/4,
        mutable = false
    )

    underlying_grid = TripolarGrid(
        arch;
        size = (Nx, Ny, Nz),
        halo = (6, 6, 5),
        z
    )

    bottom_height = regrid_bathymetry(
        underlying_grid;
        minimum_depth = 10,
        interpolation_passes = 10,
        major_basins = 2
    )

    return ImmersedBoundaryGrid(
        underlying_grid,
        GridFittedBottom(bottom_height);
        active_cells_map=true
    )
end

end
