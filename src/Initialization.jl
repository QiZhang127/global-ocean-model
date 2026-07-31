module Initialization

using CopernicusMarine
using Dates: DateTime
using Oceananigans: set!
using NumericalEarth: GLORYSMonthly,  MetadataSet, Metadatum
# using NumericalEarth: ECCO4Monthly, ECCO4DarwinMonthly, Metadatum

# TODO: GLODAP is currently a module I wrote
# I am working on getting this into NumericalEarth.DataWrangling
include("../modules/GLODAP.jl")
using .GLODAP

export initialize_ocean!

# TODO: set date correctly, it is in atmosphere right now
function initialize_ocean!(ocean, grid, date)

    # -----------------------------------------------------------------
    # initialization datasets
    # -----------------------------------------------------------------
    #ecco   = ECCO4Monthly()
    #darwin = ECCO4DarwinMonthly()
    
    # -----------------------------------------------------------------
    # data directories and files
    # -----------------------------------------------------------------
    #ecco_dir    = "/home/ljg48/project_pi_me586/ljg48/data/ecco-darwin"
    #darwin_file = "pickup_ptracers.0000210384-002.data"
    #ecco_file   = "pickup.0000210384-001.data" 
    #ice_file    = "pickup_seaice.0000210384.data"

    # -----------------------------------------------------------------
    # GLROYS fields
    # -----------------------------------------------------------------
    #date = DateTime(2000, 1)
    glorys_temperature = Metadatum(:temperature; date, dataset = GLORYSMonthly())
    glorys_salinity = Metadatum(:salinity; date, dataset = GLORYSMonthly())
    #glorys_sea_ice_thickness = Metadatum(:sea_ice_thickness; date, dataset = GLORYSMonthly())
    #glorys_sea_ice_concentration = Metadatum(:sea_ice_concentration; date, dataset = GLORYSMonthly())

    # -----------------------------------------------------------------
    # ECCO fields
    # -----------------------------------------------------------------
    #ecco_temperature           = Metadatum(:temperature; date, dataset=ecco, dir=ecco_dir, filename=ecco_file)
    #ecco_salinity              = Metadatum(:salinity; date, dataset=ecco, dir=ecco_dir, filename=ecco_file)
    #ecco_sea_ice_thickness     = Metadatum(:sea_ice_thickness; date, dataset=ecco, dir=ecco_dir, filename=ice_file)
    #ecco_sea_ice_concentration = Metadatum(:sea_ice_concentration; date, dataset=ecco, dir=ecco_dir, filename=ice_file)

    # -----------------------------------------------------------------
    # Darwin
    # -----------------------------------------------------------------
    #ecco_darwin_alk  = Metadatum(:alkalinity; date, dataset=darwin, dir=ecco_dir, filename=darwin_file)
    #ecco_darwin_dic  = Metadatum(:dissolved_inorganic_carbon; date, dataset=darwin)
    #ecco_darwin_no3  = Metadatum(:nitrate; date, dataset=darwin)
    #ecco_darwin_po4  = Metadatum(:phosphate; date, dataset=darwin)
    #ecco_darwin_dop  = Metadatum(:dissolved_organic_phosphorus; date, dataset=darwin)
    #ecco_darwin_pop  = Metadatum(:particulate_organic_phosphorus; date, dataset=darwin)
    #ecco_darwin_fet  = Metadatum(:dissolved_iron; date, dataset=darwin)
    #ecco_darwin_sio2 = Metadatum(:dissolved_silicate; date, dataset=darwin)
    #ecco_darwin_02   = Metadatum(:dissolved_oxygen; date, dataset=darwin)

    glodap_alk  = Metadatum(:alkalinity; dataset=GLODAPClimatology())
    glodap_dic  = Metadatum(:dissolved_inorganic_carbon;  dataset=GLODAPClimatology())

    # -----------------------------------------------------------------
    # initial DIC
    # FIXME: this is temporary while I figure out why ECCO Darwin
    #        is not downloading
    # -----------------------------------------------------------------
    dic_constant = 2000.0

    dic_initial = zeros(Float64, size(grid))
    dic_initial .= dic_constant

    alk_constant = 2300.0

    alk_initial = zeros(Float64, size(grid))
    alk_initial .= alk_constant

    # -----------------------------------------------------------------
    # Phytoplankton and Zooplankton
    # -----------------------------------------------------------------
    # initialize to really small value
    phytoplankton_seed_concentration = zeros(Float64, size(grid))
    phytoplankton_seed_concentration .= 0.001  # mmol N m⁻³

    # initialize to really small value
    zooplankton_seed_concentration = zeros(Float64, size(grid))
    zooplankton_seed_concentration .= 0.0002 # mmol N m⁻³

    set!(ocean.model, 
        T    = glorys_temperature,
        S    = glorys_salinity, 
        Alk1 = glodap_alk, #alk_initial, #ecco_darwin_alk, 
        DIC1 = glodap_dic, #dic_initial, #ecco_darwin_dic, 
        Alk2 = glodap_alk, #alk_initial,  #ecco_darwin_alk, 
        DIC2 = glodap_dic, #dic_initial, #ecco_darwin_dic,
        #NO₃  = ecco_darwin_no3,
        P    = phytoplankton_seed_concentration,
        Z    = zooplankton_seed_concentration)

end

end
