module BiogeochemistrySetup

import Oceananigans

using CUDA: @allowscalar
using CSV
using DataFrames
using Dates
using Oceananigans: Center, FieldBoundaryConditions, FieldTimeSeries, KernelFunctionOperation
using OceanBioME: LOBSTER, CarbonateSystem, CarbonChemistry
using OceanBioME: Nutrients, NitrateAmmonia, PO₄, Fe, Oxygen
using OceanBioME.Models.GasExchangeModel: CarbonDioxideGasExchangeBoundaryCondition, CarbonDioxideConcentration
using OceanBioME.Models.GasExchangeModel.ScaledGasTransferVelocity: ERA5
using Oceananigans.OutputReaders:
    FieldTimeSeries, Linear, TimeSeriesInterpolation

using OceanBioME.Models.GasExchangeModel:
    SchmidtScaledTransferVelocity,
    CarbonDioxidePolynomialSchmidtNumber
using Oceananigans.Fields: instantiated_location
using Oceananigans.Fields: Field
using Oceananigans.Grids: Center
using Oceananigans.Grids: AbstractGrid
using Oceananigans.OutputReaders: FlavorOfFTS, Time

export build_bgc

import OceanBioME.Models.GasExchangeModel: surface_value
import OceanBioME.Models.GasExchangeModel:
    MolPerKgPerAtmToMMolPerCubicMPerMicroAtm

import Adapt

using Oceananigans.BoundaryConditions: getbc
using OceanBioME.Light: TwoBandPhotosyntheticallyActiveRadiation

using Oceananigans.BoundaryConditions:
    FluxBoundaryCondition,
    FieldBoundaryConditions

struct LinearAtmosphericCO2{T}
    c_start::T
    slope::T
    t_start::T
    t_end::T
end

@inline function surface_value(c::LinearAtmosphericCO2,
                               i, j, grid, clock, model_fields)

    t = clamp(clock.time, c.t_start, c.t_end)

    return c.c_start + c.slope * (t - c.t_start)
end

@inline function surface_value(
    f::Tuple{FlavorOfFTS, FlavorOfFTS, <:AbstractGrid},
    i, j, grid, clock, args...
)
    uf, vf, fgrid = f

    to_time = Time(clock.time)

    target_node = Oceananigans.Grids._node(
        i, j, grid.Nz,
        grid, Center(), Center(), Center()
    )

    u = Oceananigans.Fields.interpolate(
        target_node, to_time, uf,
        instantiated_location(uf), fgrid
    )

    v = Oceananigans.Fields.interpolate(
        target_node, to_time, vf,
        instantiated_location(vf), fgrid
    )

    return sqrt(u*u + v*v)
end

using OceanBioME: ScaleNegativeTracers

nitrogen_positivity = ScaleNegativeTracers(
    (:NO₃, :NH₄, :P, :Z, :DOM, :sPOM, :bPOM);
    warn = false,
)

# Surface fields are linked during model setup.
mutable struct SurfaceDataLink
    data::Any
end

@inline Base.getindex(link::SurfaceDataLink, i, j, k) =
    getindex(link.data, i, j, k)

Adapt.adapt_structure(to, link::SurfaceDataLink) =
    Adapt.adapt(to, link.data)

struct IceLimitedFlux{B, I} <: Function
    open_water_bc::B
    ice::I
end

@inline function (f::IceLimitedFlux)(i, j, grid, clock, fields)
    A = clamp(f.ice[i, j, 1], 0, 1)

    # No gas exchange under full ice cover.
    A == one(A) && return zero(A)

    return (one(A) - A) *
           getbc(f.open_water_bc, i, j, grid, clock, fields)
end

Adapt.adapt_structure(to, f::IceLimitedFlux) =
    IceLimitedFlux(
        Adapt.adapt(to, f.open_water_bc),
        Adapt.adapt(to, f.ice),
    )

struct ShortwavePAR{S, F} <: Function
    shortwave::S
    fraction::F
end

@inline function (p::ShortwavePAR)(i, j, grid, clock, fields)
    sw = p.shortwave[i, j, 1]
    return p.fraction * max(sw, zero(sw))
end

Adapt.adapt_structure(to, p::ShortwavePAR) =
    ShortwavePAR(
        Adapt.adapt(to, p.shortwave),
        Adapt.adapt(to, p.fraction),
    )

function build_bgc(grid, atmosphere)

    ice_link = SurfaceDataLink(
        Field{Center, Center, Nothing}(grid).data
    )

    shortwave_link = SurfaceDataLink(
        Field{Center, Center, Nothing}(grid).data
    )

    ice_bgc_links = (
        ice = ice_link,
        shortwave = shortwave_link,
    )
    # Assume 43% of ocean-surface shortwave is PAR (Zhang et al., 2010).
    # doi:10.1029/2009JC005387
    light_attenuation = TwoBandPhotosyntheticallyActiveRadiation(
        grid,
        ShortwavePAR(shortwave_link, 0.43);
        discrete_form = true,
    )

    biogeochemistry = LOBSTER(
        grid;
        limiting_nutrients = (:nitrate, :ammonia, :iron),
        nutrients = Nutrients(
            nitrogen = NitrateAmmonia{eltype(grid)}(),
            phosphate = PO₄,
            iron = Fe,
        ),
        inorganic_carbon = CarbonateSystem(2),
        oxygen = Oxygen(eltype(grid)),
        light_attenuation,
        scale_negatives = false,
        modifiers = nitrogen_positivity,
    )

    carbon_chemistry = CarbonChemistry(Float64)

    co₂_solubility =
        MolPerKgPerAtmToMMolPerCubicMPerMicroAtm(
            carbon_chemistry.solubility,
            carbon_chemistry.density_function,
        )

    transfer_velocity = SchmidtScaledTransferVelocity(
        Float64;
        base_transfer_velocity = ERA5(Float64),
        schmidt_number =
            CarbonDioxidePolynomialSchmidtNumber(Float64),
        solubility = co₂_solubility,
    )

    wind_speed = (
        atmosphere.velocities.u,
        atmosphere.velocities.v,
        atmosphere.grid,
    )

    # Atmospheric CO₂
    lines = readlines("/nfs/roberts/pi/pi_ey239/qi/global-ocean-model/data/mauna-loa-observatory/mlo_spo_monthly_mean.csv")

    header = split(strip(last(filter(startswith("%"), lines)))[2:end])

    df = CSV.read(
        "/nfs/roberts/pi/pi_ey239/qi/global-ocean-model/data/mauna-loa-observatory/mlo_spo_monthly_mean.csv",
        DataFrame;
        comment = "%",
        header = Symbol.(header),
        delim = ',',
        ignorerepeated = true,
    );

    df.time = DateTime.(df.Yr, df.Mn, 15)

    simulation_start = DateTime(2000, 1, 1)
    simulation_end   = DateTime(2002, 1, 1)

    # Linear CO₂ trend between the two bracketing MLO records.
    i_start = findlast(df.time .<= simulation_start)
    i_end   = findfirst(df.time .>= simulation_end)

    isnothing(i_start) && error(
        "No atmospheric CO₂ record exists before $simulation_start"
    )

    isnothing(i_end) && error(
        "No atmospheric CO₂ record exists after $simulation_end"
    )

    i_start == i_end && error(
        "At least two atmospheric CO₂ records are required."
    )

    co2_dates = df.time[[i_start, i_end]]
    co2_data  = Float64.(df.MLO[[i_start, i_end]])

    # Milliseconds to model seconds.
    co2_times = Float64.(
        Dates.value.(co2_dates .- Ref(simulation_start))
    ) ./ 1000

    t_start = first(co2_times)
    t_end   = last(co2_times)

    c_start = first(co2_data)
    c_end   = last(co2_data)

    co2_slope = (c_end - c_start) / (t_end - t_start)

    air_concentration = LinearAtmosphericCO2(
        c_start,
        co2_slope,
        t_start,
        t_end,
    )

    # Gas exchange for the two carbonate tracer sets
    CO₂_flux1 = CarbonDioxideGasExchangeBoundaryCondition(
        Float64;
        carbon_chemistry,
        transfer_velocity,
        wind_speed,
        air_concentration,
        water_concentration = CarbonDioxideConcentration(
            Float64;
            carbon_chemistry,
            DIC = :DIC1,
            Alk = :Alk1,
        ),
    )

    CO₂_flux2 = CarbonDioxideGasExchangeBoundaryCondition(
        Float64;
        carbon_chemistry,
        transfer_velocity,
        wind_speed,
        air_concentration,
        water_concentration = CarbonDioxideConcentration(
            Float64;
            carbon_chemistry,
            DIC = :DIC2,
            Alk = :Alk2,
        ),
    )

    CO₂_flux1 = FluxBoundaryCondition(
        IceLimitedFlux(CO₂_flux1, ice_link);
        discrete_form = true,
    )

    CO₂_flux2 = FluxBoundaryCondition(
        IceLimitedFlux(CO₂_flux2, ice_link);
        discrete_form = true,
    )
    boundary_conditions = (
        DIC1 = FieldBoundaryConditions(top = CO₂_flux1),
        DIC2 = FieldBoundaryConditions(top = CO₂_flux2),
    )

    return (;
        biogeochemistry,
        boundary_conditions,
        CO₂_flux1,
        CO₂_flux2,
        ice_bgc_links,
    )
end

end
