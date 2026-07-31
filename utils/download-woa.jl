# 
# download world ocean atlas inputs
#
# author: L. Gloege
# date: 2026-07-15 
#
using WorldOceanAtlasTools
using Dates: DateTime
using NumericalEarth: WOAMonthly,  MetadataSet

using Downloads: download 

variables_to_download = (
    :temperature, 
    :salinity, 
    :phosphate, 
    :nitrate,
    :silicate,
    :dissolved_oxygen
    )

mset = MetadataSet(variables_to_download;
    dataset = WOAMonthly(),
    date    = DateTime(2000, 1)
    )

download_path = download(mset)
@info "Downloaded data to $download_path"
