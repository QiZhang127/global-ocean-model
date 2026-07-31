module CallbackSetup

using Oceananigans
using Oceananigans: iteration, TimeInterval
using Oceananigans.Utils: prettytime
using Oceananigans.Units: days
using Statistics: mean
using Printf: @sprintf

export add_progress_callback!

wall_time = Ref(time_ns())

function progress(sim)
    ocean = sim.model.ocean
    u, v, w = ocean.model.velocities
    T = ocean.model.tracers.T
    e = ocean.model.tracers.e
    Tmin, Tmax, Tavg = minimum(T), maximum(T), mean(view(T, :, :, ocean.model.grid.Nz))
    emax = maximum(e)
    umax = (maximum(abs, u), maximum(abs, v), maximum(abs, w))

    step_time = 1e-9 * (time_ns() - wall_time[])

    msg1 = @sprintf("time: %s, iter: %d", prettytime(sim), iteration(sim))
    msg2 = @sprintf(", max|uo|: (%.1e, %.1e, %.1e) m s⁻¹", umax...)
    msg3 = @sprintf(", extrema(To): (%.1f, %.1f) ᵒC, mean(To(z=0)): %.1f ᵒC", Tmin, Tmax, Tavg)
    msg4 = @sprintf(", max(e): %.2f m² s⁻²", emax)
    msg5 = @sprintf(", wall time: %s \n", prettytime(step_time))

    @info msg1 * msg2 * msg3 * msg4 * msg5

    wall_time[] = time_ns()

     return nothing
end

function add_progress_callback!(simulation)
    add_callback!(simulation, progress, TimeInterval(5days))
end

end