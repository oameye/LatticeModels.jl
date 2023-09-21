import Base: getindex, +, -, *, /
using LinearAlgebra

"""
    AbstractCurrents

Supertype for all type representing currents-like values on a lattice.
Subtypes must implement `Base.getindex(::Int, ::Int)` and `lattice` functions.
"""
abstract type AbstractCurrents end

"""
    sample(::AbstractCurrents)

Gets the lattice where the given `AbstractCurrents` object is defined.
"""
sample(curr::AbstractCurrents) = error("lattice(::$(typeof(curr))) must be explicitly implemented")

Base.getindex(curr::AbstractCurrents, s1::BravaisSite, s2::BravaisSite) =
    curr[site_index(lattice(curr), s1), site_index(lattice(curr), s2)]

"""
    SubCurrents{CT<:AbstractCurrents} <: AbstractCurrents

A lazy wrapper for a `Currents` object representing the same currents but on a smaller lattice.
"""
struct SubCurrents{CT} <: AbstractCurrents
    parent_currents::CT
    lattice::BravaisLattice
    indices::Vector{Int}
    function SubCurrents(parent_currents::CT, indices::Vector{Int}) where {CT<:AbstractCurrents}
        l = lattice(parent_currents)
        new{CT}(parent_currents, l[indices], indices)
    end
end

Base.getindex(scurr::SubCurrents, i::Int, j::Int) = scurr.parent_currents[scurr.indices[i], scurr.indices[j]]
lattice(scurr::SubCurrents) = scurr.lattice

"""
    MaterializedCurrents <: AbstractCurrents

A `AbstractCurrents` instance that stores values for all currents explicitly.
"""
struct MaterializedCurrents <: AbstractCurrents
    lattice::BravaisLattice
    currents::Matrix{Float64}
    function MaterializedCurrents(l::BravaisLattice, curs::Matrix{Float64})
        !all(length(l) .== size(curs)) && error("dimension mismatch")
        new(l, curs)
    end
end

MaterializedCurrents(l::BravaisLattice) =
    MaterializedCurrents(l, zeros(length(l), length(l)))

Base.convert(::Type{MaterializedCurrents}, curr::AbstractCurrents) = materialize(curr)
Base.copy(mc::MaterializedCurrents) = MaterializedCurrents(lattice(mc), copy(mc.currents))
Base.zero(mc::MaterializedCurrents) = MaterializedCurrents(lattice(mc), zero(mc.currents))
lattice(mcurr::MaterializedCurrents) = mcurr.lattice

Base.getindex(mcurr::MaterializedCurrents, i::Int, j::Int) = mcurr.currents[i, j]
function Base.getindex(curr::AbstractCurrents, lvm::LatticeValue{Bool})
    check_samesites(curr, lvm)
    indices = findall(lvm.values)
    SubCurrents(curr, indices)
end

function Base.getindex(curr::MaterializedCurrents, lvm::LatticeValue{Bool})
    check_samesites(curr, lvm)
    indices = findall(lvm.values)
    MaterializedCurrents(curr.lattice[lvm], curr.currents[indices, indices])
end

function _site_indices(l::BravaisLattice, l2::BravaisLattice)
    check_issublattice(l2, l)
    return [site_index(l, site) for site in l2]
end
_site_indices(l::BravaisLattice, site::BravaisSite) = (site_index(l, site),)
function currents_from(curr::AbstractCurrents, src)
    l = lattice(curr)
    is = _site_indices(l, src)
    LatticeValue(l, Float64[j in is ? 0 : sum(curr[i, j] for i in is) for j in eachindex(l)])
end
function currents_from_to(curr::AbstractCurrents, src, dst=nothing)
    l = lattice(curr)
    is = _site_indices(l, src)
    js = dst === nothing ? setdiff(eachindex(l), is) : _site_indices(l, dst)
    sum(curr[i, j] for i in is, j in js)
end

for f in (:+, :-)
    @eval function ($f)(curr::MaterializedCurrents, curr2::MaterializedCurrents)
        check_samesites(curr, curr2)
        MaterializedCurrents(lattice(curr), ($f)(curr.currents, curr2.currents))
    end
end
for f in (:*, :/)
    @eval ($f)(curr::MaterializedCurrents, num::Number) = MaterializedCurrents(lattice(curr), ($f)(curr.currents, num))
end
*(num::Number, curr::MaterializedCurrents) = curr * num

"""
    materialize([adjacency_matrix, ]currents)

Creates a `MaterializedCurrents` instance for `currents`.

If `function` is provided, it must accept a `Lattice` and two `LatticeSite`s and return if the current between this site must be calculated or not.
This can be useful to avoid exsessive calculations.
"""
function materialize(am::Nullable{AdjacencyMatrix}, curr::AbstractCurrents)
    l = lattice(curr)
    m = MaterializedCurrents(l)
    for i in eachindex(l), j in 1:i-1
        am !== nothing && !am[l[i], l[j]] && continue
        ij_curr = curr[i, j]
        m.currents[i, j] = ij_curr
        m.currents[j, i] = -ij_curr
    end
    m
end
materialize(curr::AbstractCurrents) = materialize(nothing, curr)

"""
    map_currents(map_fn, currs::AnstractCurrents[; reduce_fn, sort=false])

Accepts a function that takes a `Lattice` and two `LatticeSite`s and returns any value.
Applies `map_fn` to every site pair and returns two `Vector`s: one with currents, one with results of `map_fn`.

**Keyword arguments:**
- `reduce_fn`: if a function is provided, all currents with the same mapped value will be reduced into one value.
For example, if `aggr_fn=(x -> mean(abs.(x)))`, and `map_fn` finds the distance between the sites,
the returned lists will store the distance between sites and the average absolute current between sites with such distance.
- `sort`: if true, the output arrays will be sorted by mapped value.
"""
function map_currents(f::Function, curr::AbstractCurrents; reduce_fn::Nullable{Function}=nothing, sort::Bool=false)
    l = lattice(curr)
    cs = Float64[]
    ms = only(Base.return_types(f, (BravaisSite, BravaisSite)))[]
    for (i, site1) in enumerate(l)
        for (j, site2) in enumerate(l)
            if site1 > site2
                push!(cs, curr[i, j])
                push!(ms, f(site1, site2))
            else
                break
            end
        end
    end
    if reduce_fn !== nothing
        ms_set = unique(ms)
        cs = [reduce_fn(cs[ms .== m]) for m in ms_set]
        ms = ms_set
    end
    if sort
        perm = sortperm(ms)
        permute!(ms, perm)
        permute!(cs, perm)
    end
    if eltype(cs) <: Vector
        ms, transpose(hcat(cs...))
    else
        ms, cs
    end
end

@recipe function f(curr::AbstractCurrents)
    l = lattice(curr)
    dims(l) != 2 && error("2D lattice expected")
    Xs = Float64[]
    Ys = Float64[]
    Qs = NTuple{2,Float64}[]
    arrows_scale --> 1
    arrows_rtol --> 1e-2
    seriestype := :quiver
    for (i, site1) in enumerate(l)
        for (j, site2) in enumerate(l)
            j ≥ i && continue
            ij_curr = curr[i, j]::Real
            crd = ij_curr > 0 ? site1.coords : site2.coords
            vc = site2.coords - site1.coords
            vc_n = norm(vc)
            if vc_n < abs(ij_curr * plotattributes[:arrows_scale] / plotattributes[:arrows_rtol])
                push!(Xs, crd[1])
                push!(Ys, crd[2])
                push!(Qs, Tuple(vc * (ij_curr * plotattributes[:arrows_scale] / vc_n)))
            end
        end
    end
    quiver := Qs
    Xs, Ys
end
