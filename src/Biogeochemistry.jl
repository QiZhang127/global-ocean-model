module BiogeochemistrySetup

using CUDA: @allowscalar
using CSV
using DataFrames
using Dates
using Oceananigans: Center, FieldBoundaryConditions, FieldTimeSeries, KernelFunctionOperation
using OceanBioME: LOBSTER, CarbonateSystem, CarbonChemistry
using OceanBioME.Models.GasExchangeModel: CarbonDioxideGasExchangeBoundaryCondition, CarbonDioxideConcentration
using OceanBioME.Models.GasExchangeModel.ScaledGasTransferVelocity: JRA55

export build_bgc

function build_bgc(grid)

    biogeochemistry = LOBSTER(
        grid;
	    inorganic_carbon = CarbonateSystem(2)
    )

    # set the transfer velocity scale factor to match the wind product

    transfer_velocity = JRA55()

    # prescibe the wind speed in the gas transfer
    #wind_speed = sqrt(atmosphere.velocities.u^2 + atmosphere.velocities.v^2)

    wind_speed = 2

    # !TODO
    # need to have air_concentration in CarbonDioxideGasExchangeBoundaryCondition be prscribed
    # currently working on have it prescribed from the Mauna Loa time series.
    # for now we will set it to a constant

    #air_concentration = 420

    lines = readlines("/home/ljg48/project_pi_me586/ljg48/data/keeling/mlo_spo_monthly_mean.csv")

    header = split(strip(last(filter(startswith("%"), lines)))[2:end])

    df = CSV.read(
        "/home/ljg48/project_pi_me586/ljg48/data/keeling/mlo_spo_monthly_mean.csv",
        DataFrame;
        comment = "%",
        header = Symbol.(header),
        delim = ',',
        ignorerepeated = true,
    );

    df.time = DateTime.(df.Yr, df.Mn, 15);

    times = df.time;
    data = df.MLO;

    # TODO: figure out a way to so I do not have to do an allowscalar
    air_concentration = FieldTimeSeries{Nothing, Nothing, Nothing}(grid, times)
    @allowscalar air_concentration .= reshape(data, 1, 1, 1, length(air_concentration)) 


    # set wind speed and air concentration in here
    # -----------------------------------------------------------------
    # TODO: make these a little more descriptive instead of "flux1 and 2"
    # ALK2 is the one that is forced, see Forcing.jl
    # -----------------------------------------------------------------
    CO₂_flux1 =
        CarbonDioxideGasExchangeBoundaryCondition(;
            transfer_velocity,
            wind_speed,
            air_concentration,
            water_concentration =
                CarbonDioxideConcentration(;
                    DIC = :DIC1,
                    Alk = :Alk1
                )
        )

    CO₂_flux2 =
        CarbonDioxideGasExchangeBoundaryCondition(;
            transfer_velocity,
            wind_speed,
            air_concentration,
            water_concentration =
                CarbonDioxideConcentration(;
                    DIC = :DIC2,
                    Alk = :Alk2
                )
        )

    boundary_conditions = (;
        DIC1 = FieldBoundaryConditions(top = CO₂_flux1),
        DIC2 = FieldBoundaryConditions(top = CO₂_flux2)
    )

    # -----------------------------------------------------------------
    # calculate pCO2
    # TODO: this should be pulled out maybe and its own function
    # -----------------------------------------------------------------
    function pco2_kfo(i, j, k, grid, cc, fields)
        @inbounds begin
            DIC = fields.DIC[i, j, k]
            Alk = fields.Alk[i, j, k]
            T = fields.T[i, j, k]
            S = fields.S[i, j, k]
        end

        return cc(; DIC, Alk, T, S)
    end

    # TODO: this needs to get moved until after fields are set?
    #pco2 = KernelFunctionOperation{Center, Center, Center}(pco2_kfo, grid, CarbonChemistry(), (; DIC, Alk, T, S))

    return (; biogeochemistry, boundary_conditions, CO₂_flux1, CO₂_flux2)
end

end
