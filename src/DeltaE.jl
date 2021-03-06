# This file is a part of RRRMC.jl. License is MIT: http://github.com/carlobaldassi/RRRMC.jl/LICENCE.md

# This implements the functions needed by the BKL and RRR methods
# for the choice of the next move

module DeltaE

using ExtractMacro
using ..Common
using ..Interface

include("ArraySets.jl")
using .ArraySets

import .ArraySets: check_consistency

include("DynamicSamplers.jl")
using .DynamicSamplers

export DeltaECache, gen_ΔEcache, check_consistency, compute_staged!, apply_staged!,
       compute_reverse_probabilities!, rand_move, rand_skip, apply_move!,
       get_class_f, get_z

findk(ΔElist, dE) = findfirst(ΔElist, abs(dE))

type DeltaECache{ET,L}
    N::Int
    ΔElist::NTuple{L,ET}
    ft::Vec
    T::Vec
    z::Float64
    T′::Vec
    z′::Float64
    ascache::Vector{ArraySet}
    pos::IVec
    staged::Vector{NTuple{3,Int}}
    @inner {ET,L} function DeltaECache(X::DiscrGraph, C::Config, ΔElist::NTuple{L,ET}, β::Float64, rrr::Bool)
        N = getN(X)
        @assert C.N == N
        ascache = [ArraySet(N) for k = 1:2L]
        pos = zeros(Int, N)
        for i = 1:N
            ΔE = delta_energy(X, C, i)
            aki = findk(ΔElist, ΔE)
            #@assert aki > 0 (ΔE, ΔElist)
            upi = ΔE > 0 || (ΔE == 0 && C.s[i] == 1)
            ki = aki + L * upi
            pos[i] = ki
            push!(ascache[ki], i)
            #check_consistency(ascache[ki])
        end
        staged = empty!(Array{NTuple{3,Int}}(N))

        ft = Float64[exp(-β * ΔE) for ΔE in allΔE(X)]
        T = zeros(2L)
        z = 0.0
        for k = 1:2L
            f = get_class_f(ft, k, L)
            x = length(ascache[k]) * f
            z += x
            T[k] = x
        end
        T′ = rrr ? similar(T) : T
        z′ = z
        new(N, ΔElist, ft, T, z, T′, z′, ascache, pos, staged)
    end
end

# @generated function DeltaECache{ET}(X::DiscrGraph{ET}, C::Config, β::Float64, rrr::Bool = true)
#     ΔElist = allΔE(X)
#     Expr(:call, Expr(:curly, :DeltaECache, ET, length(ΔElist)), :X, :C, ΔElist, :β, :rrr)
# end

function DeltaECache{ET}(X::DiscrGraph{ET}, C::Config, β::Float64, rrr::Bool = true)
    ΔElist = allΔE(X)
    DeltaECache{ET,length(ΔElist)}(X, C, ΔElist, β, rrr)
end

gen_ΔEcache(X::DiscrGraph, C::Config, β::Float64, rrr::Bool = true) = DeltaECache(X, C, β, rrr)

get_z(ΔEcache::DeltaECache) = ΔEcache.z

function check_consistency{ET,L}(ΔEcache::DeltaECache{ET,L})
    @extract ΔEcache : ΔElist ascache pos
    for as in ascache
        check_consistency(as)
    end
    for (i,k) in enumerate(pos)
        @assert 1 ≤ k ≤ 2L
        as = ascache[k]
        p = as.pos[i]
        @assert 1 ≤ p ≤ length(as)
        for k1 = 1:2L
            k1 == k && continue
            as1 = ascache[k1]
            @assert as1.pos[i] == 0
        end
    end
end

get_class_f{ET,L}(ΔEcache::DeltaECache{ET,L}, k::Integer) = get_class_f(ΔEcache.ft, k, L)
get_class_f(ft::Vec, k::Integer, L::Integer) = k > L ? ft[k - L] : 1.0

function rand_skip(ΔEcache::DeltaECache)
    @extract ΔEcache : z N
    return floor(Int, Base.log1p(-rand()) / Base.log1p(-z / N))
end

function rand_move{ET,L}(ΔEcache::DeltaECache{ET,L})
    @extract ΔEcache: ΔElist ascache ft T z
    r = rand() * z
    k = 0
    cT = 0.0
    for k = 1:2L
        cT += T[k]
        r < cT && break
    end
    r < cT || while T[k] == 0
        k -= 1
    end

    if k ≤ L
        ΔE = -ΔElist[k]
    else
        ΔE = ΔElist[k - L]
    end
    move = rand(ascache[k])

    return move, ΔE
end

function apply_staged!(ΔEcache::DeltaECache)
    @extract ΔEcache : ΔElist ascache pos staged

    for (j,k0,k1) in staged
        #@assert k0 ≠ k1
        as0 = ascache[k0]
        as1 = ascache[k1]
        delete!(as0, j)
        push!(as1, j)
        pos[j] = k1
    end
    ΔEcache.T, ΔEcache.T′, ΔEcache.z = ΔEcache.T′, ΔEcache.T, ΔEcache.z′
    return ΔEcache
end

function compute_reverse_probabilities!{ET,L}(ΔEcache::DeltaECache{ET,L})
    @extract ΔEcache : staged ft T T′ z

    z′ = z
    T′ ≢ T && copy!(T′, T)
    for (_,k0,k1) in staged
        f0 = get_class_f(ft, k0, L)
        f1 = get_class_f(ft, k1, L)

        T′[k0] -= f0
        T′[k1] += f1
        z′ += f1 - f0
    end
    ΔEcache.z′ = z′

    return z′
end

function compute_staged!{ET,L}(X::DiscrGraph{ET}, C::Config, i::Int, ΔEcache::DeltaECache{ET,L})
    @extract C : N s
    @extract ΔEcache : ΔElist pos staged

    spinflip!(X, C, i)
    empty!(staged)

    @inbounds begin
        for j in neighbors(X, i)
            k0 = pos[j]
            upj0 = k0 > L

            dE1 = delta_energy(X, C, j)
            ak1 = findk(ΔElist, dE1)
            upj1 = dE1 > 0 || (dE1 == 0 && s[j] == 1)

            k1 = ak1 + L * upj1

            k0 == k1 && continue

            push!(staged, (j,k0,k1))
        end
        k0 = pos[i]
        k1 = k0 - L * (2 * (k0 > L) - 1)
        push!(staged, (i,k0,k1))
    end

    spinflip!(X, C, i)
end

function apply_move!{ET,L}(X::Union{DiscrGraph{ET},DoubleGraph{DiscrGraph{ET}}}, C::Config, move::Int, ΔEcache::DeltaECache{ET,L})
    ## equivalent to:
    #
    # compute_staged!(X, C, move, ΔEcache)
    # compute_reverse_probabilities!(ΔEcache)
    # spinflip!(X, C, move)
    # apply_staged!(ΔEcache)

    @extract C : s
    @extract ΔEcache : ΔElist ascache pos ft T z

    spinflip!(X, C, move)

    X0 = inner_graph(X)

    z′ = z
    @inbounds begin
        for j in neighbors(X0, move)
            k0 = pos[j]
            upj0 = k0 > L

            dE1 = delta_energy(X0, C, j)
            ak1 = findk(ΔElist, dE1)
            upj1 = dE1 > 0 || (dE1 == 0 && s[j] == 1)

            k1 = ak1 + L * upj1

            k0 == k1 && continue

            f0 = get_class_f(ft, k0, L)
            f1 = get_class_f(ft, k1, L)

            T[k0] -= f0
            T[k1] += f1
            z′ += f1 - f0

            as0 = ascache[k0]
            as1 = ascache[k1]
            delete!(as0, j)
            push!(as1, j)
            pos[j] = k1
        end
        k0 = pos[move]
        k1 = k0 - L * (2 * (k0 > L) - 1)

        f0 = get_class_f(ft, k0, L)
        f1 = get_class_f(ft, k1, L)

        T[k0] -= f0
        T[k1] += f1
        z′ += f1 - f0

        as0 = ascache[k0]
        as1 = ascache[k1]
        delete!(as0, move)
        push!(as1, move)
        pos[move] = k1
    end

    c = z / z′
    ΔEcache.z = z′
    return c
end

prior(x) = x > 0 ? exp(-x) : 1.0

type DeltaECacheCont{ET}
    dynsmp::DynamicSampler
    ΔEs::Vector{ET}
    β::Float64
    staged::Vector{Tuple{Int,ET,Float64}}
    @inner {ET} function DeltaECacheCont(X::AbstractGraph, C::Config, β::Float64)
        N = getN(X)
        @assert C.N == N
        ΔEs = [delta_energy(X, C, i) for i = 1:N]
        dynsmp = DynamicSampler(prior(β * ΔE) for ΔE in ΔEs)
        staged = empty!(Array{Tuple{Int,ET,Float64}}(N))
        return new(dynsmp, ΔEs, β, staged)
    end
end

# the rrr argument here is just for consistency but it's unused
gen_ΔEcache{ET}(X::AbstractGraph{ET}, C::Config, β::Float64, rrr::Bool = true) = DeltaECacheCont{ET}(X, C, β)

get_z(ΔEcache::DeltaECacheCont) = ΔEcache.dynsmp.z

function rand_skip(ΔEcache::DeltaECacheCont)
    @extract ΔEcache : dynsmp
    @extract dynsmp : z N
    return floor(Int, Base.log1p(-rand()) / Base.log1p(-z / N))
end

function rand_move(ΔEcache::DeltaECacheCont)
    @extract ΔEcache: dynsmp ΔEs

    move = rand(dynsmp)
    ΔE = ΔEs[move]
    return move, ΔE
end

function apply_staged!(ΔEcache::DeltaECacheCont)
    @extract ΔEcache : dynsmp ΔEs staged

    @inbounds for (j,ΔE,p) in staged
        ΔEs[j] = ΔE
        dynsmp[j] = p
    end
    return ΔEcache
end

function compute_reverse_probabilities!(ΔEcache::DeltaECacheCont)
    @extract ΔEcache : dynsmp staged

    z = dynsmp.z
    @inbounds for (j,_,p) in staged
        z += p - dynsmp[j]
    end

    return z
end

function compute_staged!{ET}(X::AbstractGraph{ET}, C::Config, i::Int, ΔEcache::DeltaECacheCont{ET})
    @extract C : N s
    @extract ΔEcache : β staged

    spinflip!(X, C, i)
    empty!(staged)

    ΔE = delta_energy(X, C, i)
    p = prior(β * ΔE)
    push!(staged, (i,ΔE,p))
    for j in neighbors(X, i)
        ΔE = delta_energy(X, C, j)
        p = prior(β * ΔE)
        push!(staged, (j,ΔE,p))
    end

    spinflip!(X, C, i)
end

get_inner(X, ::Type{Val{true}}) = inner_graph(X)
get_inner(X, ::Type{Val{false}}) = X

function apply_move!{ET}(X::AbstractGraph{ET}, C::Config, move::Int, ΔEcache::DeltaECacheCont{ET}, inner = Val{true})
    ## equivalent to:
    #
    # compute_staged!(X, C, move, ΔEcache)
    # compute_reverse_probabilities!(ΔEcache)
    # spinflip!(X, C, move)
    # apply_staged!(ΔEcache)

    @extract C : s
    @extract ΔEcache : dynsmp ΔEs β

    spinflip!(X, C, move)

    X0 = get_inner(X, inner)

    z = dynsmp.z
    @inbounds begin
        ΔE = delta_energy(X0, C, move)
        ΔEs[move] = ΔE
        dynsmp[move] = prior(β * ΔE)

        for j in neighbors(X0, move)
            ΔE = delta_energy(X0, C, j)
            ΔEs[j] = ΔE
            dynsmp[j] = prior(β * ΔE)
        end
    end
    z′ = dynsmp.z
    c = z / z′
    return c
end

end # module
