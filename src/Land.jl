module LandSetup

using NumericalEarth.DataWrangling.JRA55: JRA55PrescribedLand

export build_land

function build_land(arch)

    land = JRA55PrescribedLand(arch)

    return (; land)
end

end