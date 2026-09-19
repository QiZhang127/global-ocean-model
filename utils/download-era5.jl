#
# download ERA5
# author: L. Gloege
# date: 2026-07-23
#

#using CopernicusMarine
using CopernicusClimateDataStore
using Dates
using Dates: DateTime
using Downloads: download 
using Oceananigans
using Oceananigans.Units
using NumericalEarth
using NumericalEarth: MetadataSet
using OceanBioME
using Printf
# using NumericalEarth.DataWrangling.ERA5: ERA5MonthlySingleLevel
using NumericalEarth.DataWrangling.ERA5: ERA5HourlySingleLevel

# dataset = ERA5MonthlySingleLevel()
dataset = ERA5HourlySingleLevel()

# dates = DateTime(2000,1,1):Month(1):DateTime(2006,1,1)
dates = DateTime(2000, 1, 1):Hour(1):DateTime(2006, 1, 1)

variables_names = (
    :eastward_velocity,
    :northward_velocity,
    :temperature,
    :dewpoint_temperature,
    :surface_pressure,
    :total_precipitation,
    :downwelling_shortwave_radiation,
    :downwelling_longwave_radiation
    )

download_paths = map(dates) do date
    @info "Downloading ERA5 for $date"

    mset = MetadataSet(
        variables_names;
        dataset,
        date
    )

    download(mset)
end

@info "Finished downloading ERA5 data"
