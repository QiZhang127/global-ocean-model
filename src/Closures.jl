module ClosureSetup

using Oceananigans.TurbulenceClosures: IsopycnalSkewSymmetricDiffusivity, AdvectiveFormulation
using NumericalEarth.Oceans: default_ocean_closure

export build_closure

function build_closure()

    eddy = IsopycnalSkewSymmetricDiffusivity(
        κ_skew=1e3,
        # κ_symmetric=1e3,
        κ_symmetric = (
            T = 1e3, S = 1e3, e = 1e3,
            NO₃ = 0.0, NH₄ = 0.0, Fe = 0.0,
            PO₄ = 0.0, O₂ = 0.0,
            P = 0.0, Z = 0.0,
            DOM = 0.0, sPOM = 0.0, bPOM = 0.0,
            DIC1 = 1e3, DIC2 = 1e3,
            Alk1 = 1e3, Alk2 = 1e3,
        ),
        skew_flux_formulation=AdvectiveFormulation()
    )

    vertical = default_ocean_closure()

    closure = (eddy, vertical)
    
    return closure
end

end
