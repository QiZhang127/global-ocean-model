#
# download GLORYS
# author: L. Gloege
# date: 2026-07-15
#
using CopernicusMarine
using Dates: DateTime
using NumericalEarth: GLORYSMonthly,  MetadataSet

using Downloads: download 

variables_to_download = (
    :temperature, 
    :salinity, 
   # :depth, bug in the code, deptho does not exist 
    :sea_ice_concentration,
    :sea_ice_thickness,
    :u_velocity,
    :v_velocity,
    :sea_ice_u_velocity,
    :sea_ice_v_velocity,
    :free_surface
    )

mset = MetadataSet(variables_to_download;
    dataset = GLORYSMonthly(),
    date    = DateTime(2000, 1)
    )

download_path = download(mset)
@info "Downloaded data to $download_path"
