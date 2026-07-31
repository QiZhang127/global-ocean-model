module ClosureSetup

using Oceananigans.TurbulenceClosures: IsopycnalSkewSymmetricDiffusivity, AdvectiveFormulation
using NumericalEarth.Oceans: default_ocean_closure

export build_closure

function build_closure()

    eddy = IsopycnalSkewSymmetricDiffusivity(
        κ_skew=1e3,
        κ_symmetric=1e3,
        skew_flux_formulation=AdvectiveFormulation()
    )

    vertical = default_ocean_closure()

    closure = (eddy, vertical)
    
    return closure
end

end
