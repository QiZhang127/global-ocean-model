module ForcingSetup

using MPI
using Oceananigans: Forcing, nodes, Center
using Oceananigans.Architectures: CPU, architecture, on_architecture
using Oceananigans.ImmersedBoundaries: immersed_cell

export build_alkalinity_forcing

function gaussian_forcing(amplitude, i0, j0, k0, sigma,
                          joffset, Nx, ti, tf)

    # Release times are in days; the model clock uses seconds.
    t_start = ti * 86400
    t_end = tf * 86400

    @inline function source(i, j, k, grid, clock, fields)
        # Add alkalinity only to surface wet cells during the release.
        if !(t_start <= clock.time <= t_end) ||
           k != k0 || immersed_cell(i, j, k, grid)
            return zero(amplitude)
        end

        # Wrap across the periodic x boundary and use global y indices.
        di = mod(i - i0, Nx)
        di = min(di, Nx - di)
        dj = j + joffset - j0

        # sigma is in grid cells; amplitude is the peak source rate.
        return amplitude * exp(-(di^2 + dj^2) / (2 * sigma^2))
    end

    return Forcing(source, discrete_form = true)
end

function build_alkalinity_forcing(grid;
                                  amplitude,
                                  lon,
                                  lat,
                                  sigma,
                                  ti,
                                  tf,
                                  max_center_distance_km = 100.0)

    MPI.Initialized() || error("Initialize MPI in the main script.")

    @assert all(isfinite, (amplitude, lon, lat, sigma, ti, tf,
                          max_center_distance_km))
    @assert sigma > 0 && tf >= ti && -90 <= lat <= 90
    @assert max_center_distance_km > 0

    comm = MPI.COMM_WORLD
    rank = MPI.Comm_rank(comm)
    arch = architecture(grid)

    # The index offsets below assume the grid is split only in y.
    @assert arch.ranks[1] == 1 && arch.ranks[3] == 1

    # Local j restarts on each rank; recover its global position.
    parts = reshape(
        MPI.Allgather(Int[arch.local_index[2], grid.Ny], comm),
        2, :
    )
    @assert sort(vec(parts[1, :])) == collect(1:MPI.Comm_size(comm))

    joffset = sum(parts[2, parts[1, :] .< arch.local_index[2]])

    # Search the 2D coordinates to support curved grids and avoid land.
    cpu_grid = on_architecture(CPU(), grid)
    xc, yc, _ = nodes(cpu_grid, Center(), Center(), Center())
    x, y = Array(xc), Array(yc)

    @assert size(x) == size(y) == (grid.Nx, grid.Ny)

    i0, j0 = 1, 1
    best = Inf

    for j in 1:grid.Ny, i in 1:grid.Nx
        immersed_cell(i, j, grid.Nz, cpu_grid) && continue

        λ, φ = x[i, j], y[i, j]
        (isfinite(λ) && isfinite(φ)) || continue

        # Great-circle distance metric, including longitude wraparound.
        d = sind((φ - lat) / 2)^2 +
            cosd(φ) * cosd(lat) * sind((λ - lon) / 2)^2
        d = clamp(d, 0.0, 1.0)

        if d < best
            best = d
            i0, j0 = i, j
        end
    end

    # Choose one source center across all ranks; resolve ties by rank.
    global_best = MPI.Allreduce(best, min, comm)
    isfinite(global_best) || error("No wet source cell found.")

    owner = MPI.Allreduce(
        best == global_best ? rank : typemax(Int), min, comm
    )

    # Reject a wet cell too far from the requested release location.
    distance_km = 2 * 6371.0 * asin(sqrt(global_best))
    distance_km <= max_center_distance_km ||
        error("Nearest wet cell is $(distance_km) km from the target.")

    # All ranks must use the same global source center.
    center = Int[i0, j0 + joffset]
    MPI.Bcast!(center, comm; root = owner)

    if rank == owner
        @info(
            "Source center",
            owner_rank = owner,
            global_index = (center[1], center[2], grid.Nz),
            lon = mod(x[i0, j0] + 180, 360) - 180,
            lat = y[i0, j0],
            distance_km = distance_km,
            sigma = sigma,
        )
    end

    # Each rank evaluates its part of one global Gaussian.
    alk_forcing = gaussian_forcing(
        amplitude, center[1], center[2], grid.Nz,
        sigma, joffset, grid.Nx, ti, tf,
    )

    return (; Alk2 = alk_forcing)
end

end
