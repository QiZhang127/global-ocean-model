#using CDSAPI
using CopernicusClimateDataStore
using Dates
using Dates: DateTime
using Oceananigans
using Oceananigans.Units
using NumericalEarth
using OceanBioME
using Printf
using NumericalEarth.DataWrangling.ERA5: ERA5PrescribedAtmosphere, ERA5PrescribedRadiation, ERA5MonthlySingleLevel

dates = DateTime(2000,1,1):Month(1):DateTime(2006,1,1)

arch = CPU()

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

