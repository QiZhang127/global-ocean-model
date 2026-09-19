module Initialization

using Oceananigans.Architectures: CPU, on_architecture
using Oceananigans.Grids: inactive_cell
using CopernicusMarine
using Oceananigans: set!
using NumericalEarth: GLORYSMonthly,  MetadataSet, Metadatum
using NumericalEarth: ECCO4DarwinMonthly

using Dates: DateTime, year, month
using NCDatasets: NCDataset, dimnames
using Oceananigans.Grids: nodes
using Oceananigans.Fields: interior
using Oceananigans.TimeSteppers: update_state!
using MPI

export initialize_ocean!, initialize_sea_ice!

# Surface salinity defines the GLORYS ocean mask.
function read_glorys_surface_mask(path, date)
    isfile(path) || error("File not found: $path")

    return NCDataset(path, "r") do ds
        v = ds["so"]

        @assert dimnames(v) ==
                ("longitude", "latitude", "depth", "time")
        @assert size(v, 4) == 1

        t = only(ds["time"][:])
        @assert (year(t), month(t)) == (year(date), month(date))

        # Read the shallowest salinity layer only.
        k = argmin(ds["depth"][:])
        S = Float64.(coalesce.(v[:, :, k, 1], NaN))

        lon = mod.(Float64.(ds["longitude"][:]), 360)
        lat = Float64.(ds["latitude"][:])

        ix = sortperm(lon)
        iy = sortperm(lat)

        return lon[ix], lat[iy], isfinite.(S[ix, iy])
    end
end

function read_glorys_ice(path, name, date)
    isfile(path) || error("File not found: $path")

    return NCDataset(path, "r") do ds
        v = ds[name]
        dims = String.(dimnames(v))

        for axis in ("longitude", "latitude")
            axis in dims || error("$name: missing $axis dimension")
        end

        # Only longitude and latitude may have multiple entries.
        for d in eachindex(dims)
            if !(dims[d] in ("longitude", "latitude"))
                size(v, d) == 1 ||
                    error("$name: expected one time slice; found $(size(v))")
            end
        end

        expected_units = name == "siconc" ? "1" : "m"
        units = strip(String(get(v.attrib, "units", "")))
        units == expected_units ||
            error("$name: expected units '$expected_units', found '$units'")

        t = only(ds["time"][:])
        (year(t), month(t)) == (year(date), month(date)) ||
            error("$name: file month does not match initialization date")

        selection = map(dims) do d
            d in ("longitude", "latitude") ? Colon() : 1
        end

        # NCDatasets decodes fill values and scale/offset automatically.
        values = Float64.(coalesce.(Array(v[selection...]), NaN))

        horizontal_dims = filter(
            d -> d in ("longitude", "latitude"), dims
        )
        if first(horizontal_dims) == "latitude"
            values = permutedims(values)
        end

        lon = mod.(Float64.(ds["longitude"][:]), 360)
        lat = Float64.(ds["latitude"][:])

        ix = sortperm(lon)
        iy = sortperm(lat)
        lon, lat = lon[ix], lat[iy]
        values = values[ix, iy]

        all(diff(lon) .> 0) || error("Invalid longitude coordinates")
        all(diff(lat) .> 0) || error("Invalid latitude coordinates")

        # This initializer expects the global GLORYS files.
        largest_gap = maximum(diff(vcat(lon, lon[1] + 360)))
        largest_gap < 2 * 360 / length(lon) ||
            error("Longitude coverage is not global")

        any(x -> isfinite(x) && x < 0, values) &&
            error("$name contains negative values")

        if name == "siconc"
            finite_values = filter(isfinite, vec(values))
            isempty(finite_values) && error("No finite siconc values")

            max_before = maximum(finite_values)

            # Allow small overshoots in this input; reject values above 1.03.
            max_before <= 1.03 || error(
                "Unexpected siconc maximum=$max_before; inspect before clipping."
            )

            above_one = isfinite.(values) .& (values .> 1.0)
            values[above_one] .= 1.0
        end

        return lon, lat, values
    end
end

function initialize_sea_ice!(sea_ice, date;
                             glorys_dir,
                             comm = MPI.COMM_WORLD,
                             max_distance_km = 100.0)

    stamp = replace(string(date), ":" => "-")
    suffix = "_GLORYSMonthly_$(stamp)_$(stamp).nc"

    lon, lat, A = read_glorys_ice(
        joinpath(glorys_dir, "siconc" * suffix), "siconc", date
    )
    lon_h, lat_h, H = read_glorys_ice(
        joinpath(glorys_dir, "sithick" * suffix), "sithick", date
    )

    (lon == lon_h && lat == lat_h) ||
        error("Thickness and concentration grids do not match")
    lon_s, lat_s, source_wet = read_glorys_surface_mask(
        joinpath(glorys_dir, "so" * suffix), date
    )

    (lon == lon_s && lat == lat_s) ||
        error("Salinity and sea-ice grids do not match")

    # Fill missing concentration as ice-free only over source ocean
    # where thickness is also missing or zero.
    icefree_fill = source_wet .&
                   .!isfinite.(A) .&
                   (.!isfinite.(H) .| (H .== 0))

    A[icefree_fill] .= 0.0
    H[icefree_fill] .= 0.0

    # Keep source land excluded from nearest-neighbour searches.
    A[.!source_wet] .= NaN
    H[.!source_wet] .= NaN

    model = sea_ice.model
    hfield = model.ice_thickness

    # Use local grid coordinates so mapping is independent of rank order.
    λ, φ, _ = nodes(hfield; with_halos=false)
    nx, ny, _ = size(hfield)
    λ = reshape(Array(λ), nx, ny)
    φ = reshape(Array(φ), nx, ny)

    h_initial = fill(NaN, nx, ny, 1)
    A_initial = fill(NaN, nx, ny, 1)
    # Exclude model land from the search.
    cpu_grid = on_architecture(CPU(), hfield.grid)
    Nz = size(cpu_grid, 3)

    wet = reshape(
        [!inactive_cell(i, j, Nz, cpu_grid)
         for i in 1:nx, j in 1:ny],
        nx, ny, 1
    )

    h_initial[.!wet] .= 0.0
    A_initial[.!wet] .= 0.0

    south = lat[1] - (lat[2] - lat[1]) / 2
    north = lat[end] + (lat[end] - lat[end-1]) / 2

    searched = falses(nx, ny, 1)
    nearby_source_wet = falses(nx, ny, 1)

    angular_radius = rad2deg(max_distance_km / 6371.0)

    for j in 1:ny, i in 1:nx
        wet[i, j, 1] || continue

        # Invalid coordinates must not trigger the zero-ice fallback.
        isfinite(λ[i, j]) && isfinite(φ[i, j]) || continue

        x = mod(λ[i, j], 360)
        y = φ[i, j]

        # Require the model cell to be within the source latitude coverage.
        south <= y <= north || continue
        searched[i, j, 1] = true

        ic = clamp(searchsortedfirst(lon, x), 1, length(lon))

        jlo = max(1, searchsortedfirst(lat, y - angular_radius))
        jhi = min(length(lat), searchsortedlast(lat, y + angular_radius))

        if abs(y) + angular_radius >= 90
            lon_indices = 1:length(lon)
        else
            lon_radius = asind(clamp(
                sind(angular_radius) / cosd(y), 0.0, 1.0
            ))
            ni = ceil(Int, lon_radius / (360.0 / length(lon))) + 2
            lon_indices = (ic-ni):(ic+ni)
        end

        best_distance = Inf
        best_A = NaN
        best_h = NaN

        for jj in jlo:jhi, ii0 in lon_indices
            ii = mod1(ii0, length(lon))
            source_wet[ii, jj] || continue

            q = sind((lat[jj] - y) / 2)^2 +
                cosd(y) * cosd(lat[jj]) *
                sind((lon[ii] - x) / 2)^2

            distance = 2 * 6371.0 * asin(sqrt(clamp(q, 0.0, 1.0)))
            distance <= max_distance_km || continue

            # Distinguish absent source ocean from invalid ice data.
            nearby_source_wet[i, j, 1] = true

            a = A[ii, jj]
            h = H[ii, jj]

            isfinite(a) || continue

            if a == 0
                h = 0.0
            elseif !(isfinite(h) && h > 0)
                continue
            end

            if distance < best_distance
                best_distance = distance
                best_A = a
                best_h = h
            end
        end

        A_initial[i, j, 1] = best_A
        h_initial[i, j, 1] = best_h
    end

    # Assume ice-free only where no source ocean cell is within the radius.
    icefree_fallback = wet .& searched .&
                       .!nearby_source_wet .&
                       isnan.(A_initial) .&
                       isnan.(h_initial)

    h_initial[icefree_fallback] .= 0.0
    A_initial[icefree_fallback] .= 0.0

    set!(model; h=h_initial, ℵ=A_initial)

    # Mask model land cells and exchange halos on all MPI ranks.
    update_state!(model)

    h_check = Array(interior(model.ice_thickness))
    A_check = Array(interior(model.ice_concentration))

    bad = wet .&
      (.!isfinite.(h_check) .| .!isfinite.(A_check))
    local_bad = count(bad)
    total_bad = MPI.Allreduce(local_bad, +, comm)

    total_bad == 0 ||
        error("No valid nearby GLORYS data for $total_bad ocean cells.")

    return nothing
end

# Clip negative initial nitrate before the nitrogen-pool positivity modifier runs.
function initialize_ecco_nitrate!(field, metadata)
    set!(field, metadata)
    values = Array(interior(field))
    cpu_grid = on_architecture(CPU(), field.grid)
    wet = [!inactive_cell(i, j, k, cpu_grid)
           for i in axes(values, 1), j in axes(values, 2), k in axes(values, 3)]

    comm = MPI.COMM_WORLD
    bad = wet .& .!isfinite.(values)
    bad_count = count(bad)
    if MPI.Allreduce(bad_count, +, comm) > 0
        error("ECCO nitrate contains nonfinite ocean values; initialization stopped.")
    end

    negative = wet .& (values .< 0)
    values[negative] .= 0

    set!(field, values)
    return nothing
end

function initialize_ocean!(ocean, grid, date)

    darwin = ECCO4DarwinMonthly()

    # GLORYS physical fields
    glorys_temperature = Metadatum(:temperature; date, dataset = GLORYSMonthly())
    glorys_salinity = Metadatum(:salinity; date, dataset = GLORYSMonthly())
    glorys_sea_ice_thickness = Metadatum(:sea_ice_thickness; date, dataset = GLORYSMonthly())
    glorys_sea_ice_concentration = Metadatum(:sea_ice_concentration; date, dataset = GLORYSMonthly())

    # ECCO Darwin biogeochemical fields
    ecco_darwin_alk  = Metadatum(:alkalinity; date, dataset=darwin)
    ecco_darwin_dic  = Metadatum(:dissolved_inorganic_carbon; date, dataset=darwin)
    ecco_darwin_no3  = Metadatum(:nitrate; date, dataset=darwin)
    ecco_darwin_po4  = Metadatum(:phosphate; date, dataset=darwin)
    ecco_darwin_fet  = Metadatum(:dissolved_iron; date, dataset=darwin)
    ecco_darwin_o2   = Metadatum(:dissolved_oxygen; date, dataset=darwin)

    NH₄_initial = 0.001

    # Small P and Z seeds, concentrated in the upper ocean (mmol N m⁻³).
    upper_ocean_weight(z) =
        0.5 * (1 + tanh((z + 100) / 30))

    P_initial(x, y, z) =
        0.001 + (0.01 - 0.001) * upper_ocean_weight(z)

    Z_initial(x, y, z) =
        0.0001 + (0.001 - 0.0001) * upper_ocean_weight(z)

    # Handle negative nitrate before set! updates the biological state.
    initialize_ecco_nitrate!(ocean.model.tracers.NO₃, ecco_darwin_no3)

    set!(ocean.model,
        T    = glorys_temperature,
        S    = glorys_salinity,
        Alk1 = ecco_darwin_alk,
        DIC1 = ecco_darwin_dic,
        Alk2 = ecco_darwin_alk,
        DIC2 = ecco_darwin_dic,
        P    = P_initial,
        Z    = Z_initial,
        NH₄ = NH₄_initial,
        Fe = ecco_darwin_fet,
        PO₄ = ecco_darwin_po4,
        O₂ = ecco_darwin_o2,
    )

end

end
