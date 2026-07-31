module AtmosphereSetup

#using CDSAPI
using CopernicusClimateDataStore
using Dates: DateTime
using NumericalEarth.DataWrangling.ERA5: ERA5PrescribedAtmosphere, ERA5PrescribedRadiation, ERA5MonthlySingleLevel

export build_atmosphere

function build_atmosphere(arch, dates)

    dataset = ERA5MonthlySingleLevel()

    atmosphere = ERA5PrescribedAtmosphere(
        arch;
        dataset,
        start_date=first(dates),
        end_date=last(dates)
    )

    radiation = ERA5PrescribedRadiation(
        arch;
        dataset,
        start_date=first(dates),
        end_date=last(dates)
    )

    return (; atmosphere, radiation)
end

end
