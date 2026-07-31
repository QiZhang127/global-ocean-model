#using CDSAPI
using CopernicusClimateDataStore
using Dates: DateTime
using NumericalEarth: ECCO4Monthly, ECCO4DarwinMonthly, MetadataSet

using Downloads: download 

variables_to_download = (
    :temperature, 
    :salinity, 
    :sea_ice_thickness, 
    :sea_ice_concentration
    )

mset = MetadataSet(variables_to_download;
    dataset = ECCO4Monthly(),
    date    = DateTime(2000, 1)
    )

download_path = download(mset)
@info "Downloaded data to $download_path"
