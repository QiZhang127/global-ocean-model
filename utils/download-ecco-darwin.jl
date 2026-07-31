#using CDSAPI
using CopernicusClimateDataStore
using Dates: DateTime
using NumericalEarth: ECCO4Monthly, ECCO4DarwinMonthly, MetadataSet

using Downloads: download 

variables_to_download = (
    :alkalinity, 
    :dissolved_inorganic_carbon, 
    :nitrate,:phosphate, 
    :dissolved_organic_phosphorus, 
    :particulate_organic_phosphorus, 
    :dissolved_iron,:dissolved_silicate, 
    :dissolved_oxygen
    )

mset = MetadataSet(variables_to_download;
    dataset = ECCO4DarwinMonthly(),
    date    = DateTime(2000, 1, 1)
    )

download_path = download(mset)
@info "Downloaded temperature data to $download_path"



#using NumericalEarth
#using Oceananigans
#using CopernicusMarine

#arch = CPU()
#Nx = 20 * 12
#Ny = 20 * 12
#Nz = 50

#depth = 6000
#z = ExponentialDiscretization(Nz, -depth, 0; scale=depth/4.5)

#grid = LatitudeLongitudeGrid(arch;
#                             size = (Nx, Ny, Nz),
#                             halo = (7, 7, 7),
#                             z,
#                             latitude  = (35, 55),
#                             longitude = (200, 220))

#region = NumericalEarth.DataWrangling.BoundingBox(longitude=(200, 220), latitude=(35, 55))

# dataset = NumericalEarth.DataWrangling.Copernicus.GLORYSStatic()
# static_meta = NumericalEarth.DataWrangling.Metadatum(:depth; dataset, region)
# coords_path = download(static_meta)
# @info "Downloaded coordinates data to $coords_path"

# T_ecco = NumericalEarth.DataWrangling.ECCOMetadatum(:temperature; dataset, region)
# T_en4_meta = NumericalEarth.DataWrangling.EN4Metadatum(:temperature)
# T_en4_path = download(T_en4_meta)
# T_en4 = Field(T_en4_meta)

#dataset = NumericalEarth.DataWrangling.Copernicus.GLORYSDaily()
#T_meta = NumericalEarth.DataWrangling.Metadatum(:temperature; dataset, region)
#T_path = download(T_meta)
#@info "Downloaded temperature data to $T_path"
#T = Field(T_meta, inpainting=nothing)
