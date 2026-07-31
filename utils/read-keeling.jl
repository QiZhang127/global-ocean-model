
using CSV
using Dates
using DataFrames
using Interpolations

filename = "/home/ljg48/project_pi_me586/ljg48/data/keeling/mlo_spo_monthly_mean.csv"
data = CSV.read(filename, DataFrame)

co2 = Dict((r.year, r.month) => r.concentration for r in eachrow(data))

const model_start = Date(2000, 1, 1)

function air_concentration(x, y, t)
    d = model_start + Day(floor(Int, t / 86400))
    return co2[(year(d), month(d))]
end


function make_air_concentration(data, model_start)
    co2 = Dict((r.year, r.month) => r.concentration for r in eachrow(data))

    return function (x, y, t)
        d = model_start + Day(floor(Int, t / 86400))
        return co2[(year(d), month(d))]
    end
end

air_concentration = make_air_concentration(data, Date(2000, 1, 1))

function abmult3(r::Int)
    if r < 0
        r = -r
    end
    f = let r = r
            x -> x * r
    end
    return f
end


struct AirConcentration
    co2::Dict{Tuple{Int,Int},Float64}
    model_start::Date
end

function (ac::AirConcentration)(x, y, t)
    d = ac.model_start + Day(floor(Int, t / 86400))
    return ac.co2[(year(d), month(d))]
end


co2 = Dict((r.year, r.month) => r.concentration for r in eachrow(data))

air_concentration = AirConcentration(co2, Date(2000, 1, 1))



dates = [Date(r.year, r.month, 1) for r in eachrow(keeling)]

times = Float64[(d - model_start).value * 86400 for d in dates]

co2_values = keeling.concentration

itp = linear_interpolation(
    times,
    co2_values,
    extrapolation_bc = Flat()
)

air_concentration(x, y, t) = itp(t)