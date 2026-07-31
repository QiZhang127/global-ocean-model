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
using NumericalEarth.DataWrangling.ERA5: ERA5MonthlySingleLevel

dataset = ERA5MonthlySingleLevel()

dates = DateTime(2000,1,1):Month(1):DateTime(2006,1,1)

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

mset = MetadataSet(variables_names;
    dataset,
    dates 
    )

download_path = download(mset)
@info "Downloaded data to $download_path"
