using LinearAlgebra, Logging, QuantumOpticsBase

struct LatticeValueWrapper{LT<:AbstractLattice, VT<:AbstractVector}
    latt::LT
    values::VT
    function LatticeValueWrapper(latt::LT, values::VT) where {LT,VT}
        length(latt) != length(values) &&
            throw(DimensionMismatch("vector has length $(length(values)), lattice has length $(length(latt))"))
        new{LT,VT}(latt, values)
    end
end

lattice(lvw::LatticeValueWrapper) = lvw.latt

Base.copy(lvw::LatticeValueWrapper) = LatticeValueWrapper(lvw.latt, copy(lvw.values))
Base.length(lvw::LatticeValueWrapper) = length(lvw.values)
Base.size(lvw::LatticeValueWrapper) = size(lvw.values)
function Base.getindex(lvw::LatticeValueWrapper, site::AbstractSite)
    i = site_index(lattice(lvw), site)
    i === nothing && throw(BoundsError(lvw, site))
    return lvw.values[i]
end
function Base.setindex!(lvw::LatticeValueWrapper, rhs, site::AbstractSite)
    i = site_index(lattice(lvw), site)
    i === nothing && throw(BoundsError(lvw, site))
    lvw.values[i] = rhs
end
Base.eltype(lvw::LatticeValueWrapper) = eltype(lvw.values)
Base.eachindex(lvw::LatticeValueWrapper) = lattice(lvw)
Base.iterate(lvw::LatticeValueWrapper, s...) = iterate(lvw.values, s...)
Base.pairs(lvw::LatticeValueWrapper) = Iterators.map(=>, lvw.latt, lvw.values)
Base.keys(lvw::LatticeValueWrapper) = lvw.latt
Base.values(lvw::LatticeValueWrapper) = lvw.values

"""
    LatticeValue{T, LT}

Represents a value of type `T` on a `LT` lattice.

## Fields
- lattice: the `AbstractLattice` object the value is defined on
- values: the values on different sites
"""
const LatticeValue{T, LT} = LatticeValueWrapper{LT, Vector{T}}

"""
    LatticeValue(lat, values)

Constructs a LatticeValue object.

## Arguments
- `lat`: the lattice the value is defined on.
- `values`: an `AbstractVector` of values on the lattice.
"""
LatticeValue(l::AbstractLattice, v::AbstractVector) = LatticeValueWrapper(l, convert(Vector, v))
LatticeValue(lf, l::AbstractLattice) = LatticeValueWrapper(l, [lf(site) for site in l])

"""
    coord_values(l::Lattice)

Generates a tuple of `LatticeValue`s representing spatial coordinates.
"""
coord_values(l::AbstractLattice) =
    [LatticeValue(l, vec) for vec in eachrow(collect_coords(l))]
siteproperty_value(l::AbstractLattice, a::SiteProperty) = LatticeValue(l, [getsiteproperty(site, a) for site in l])
siteproperty_value(l::AbstractLattice, sym::Symbol) =
    siteproperty_value(l, SitePropertyAlias{sym}())
coord_value(l::AbstractLattice, i::Int) = siteproperty_value(l, Coord(i))
coord_value(l::AbstractLattice, sym::Symbol) = siteproperty_value(l, SitePropertyAlias{sym}())

Base.rand(l::AbstractLattice) = LatticeValue(l, rand(length(l)))
Base.rand(T::Type, l::AbstractLattice) = LatticeValue(l, rand(T, length(l)))
Base.randn(l::AbstractLattice) = LatticeValue(l, randn(length(l)))
Base.randn(T::Type, l::AbstractLattice) = LatticeValue(l, randn(T, length(l)))
Base.fill(value, l::AbstractLattice) = LatticeValue(l, fill(value, length(l)))
Base.fill!(lv::LatticeValue, value) = (fill!(lv.values, value); lv)
Base.zero(lvw::LatticeValueWrapper) = LatticeValueWrapper(lattice(lvw), zero(lvw.values))
Base.zeros(T::Type, l::AbstractLattice) = fill(zero(T), l)
Base.zeros(l::AbstractLattice) = zeros(Float64, l)
Base.one(lvw::LatticeValueWrapper) = LatticeValueWrapper(lattice(lvw), one(lvw.values))
Base.ones(T::Type, l::AbstractLattice) = fill(one(T), l)
Base.ones(l::AbstractLattice) = ones(Float64, l)

Base.:(==)(lvw1::LatticeValueWrapper, lvw2::LatticeValueWrapper) = (lvw1.latt == lvw2.latt) && (lvw1.values == lvw2.values)

struct LatticeStyle <: Broadcast.BroadcastStyle end
Base.copyto!(lvw::LatticeValueWrapper, src::Broadcast.Broadcasted{LatticeStyle}) = (copyto!(lvw.values, src); return lvw)
Base.copyto!(lvw::LatticeValueWrapper, src::Broadcast.Broadcasted{Broadcast.DefaultArrayStyle{0}}) = (copyto!(lvw.values, src); return lvw)
Base.setindex!(lvw::LatticeValueWrapper, rhs, i::Int) = setindex!(lvw.values, rhs, i)
Base.broadcastable(lvw::LatticeValueWrapper) = lvw
Base.broadcastable(l::AbstractLattice) = l
Base.getindex(lvw::LatticeValueWrapper, i::CartesianIndex{1}) = lvw.values[only(Tuple(i))]
Base.getindex(l::AbstractLattice, i::CartesianIndex{1}) = l[only(Tuple(i))]
Base.BroadcastStyle(::Type{<:LatticeValueWrapper}) = LatticeStyle()
Base.BroadcastStyle(::Type{<:AbstractLattice}) = LatticeStyle()
Base.BroadcastStyle(bs::Broadcast.BroadcastStyle, ::LatticeStyle) =
    throw(ArgumentError("cannot broadcast LatticeValue along style $bs"))
Base.BroadcastStyle(::Broadcast.DefaultArrayStyle{0}, ::LatticeStyle) = LatticeStyle()

function Base.similar(bc::Broadcast.Broadcasted{LatticeStyle}, ::Type{Eltype}) where {Eltype}
    l = _extract_lattice(bc)
    LatticeValue(l, similar(Vector{Eltype}, axes(bc)))
end
_extract_lattice(bc::Broadcast.Broadcasted) = _extract_lattice(bc.args)
_extract_lattice(ext::Broadcast.Extruded) = _extract_lattice(ext.x)
_extract_lattice(lv::LatticeValueWrapper) = lv.latt
_extract_lattice(x) = x
_extract_lattice(::Tuple{}) = nothing
_extract_lattice(args::Tuple) =
    _extract_lattice(_extract_lattice(args[begin]), Base.tail(args))
_extract_lattice(::Any, rem_args::Tuple) = _extract_lattice(rem_args)
_extract_lattice(l::AbstractLattice, rem_args::Tuple) =
    _extract_lattice_s(l, rem_args)

_extract_lattice_s(l::AbstractLattice, args::Tuple) =
    _extract_lattice_s(l, _extract_lattice(args[begin]), Base.tail(args))
_extract_lattice_s(l::AbstractLattice, ::Tuple{}) = l
_extract_lattice_s(l::AbstractLattice, ::Any, rem_args::Tuple) =
    _extract_lattice_s(l, rem_args)
function _extract_lattice_s(l::AbstractLattice, l2::AbstractLattice, rem_args::Tuple)
    check_samelattice(l, l2)
    _extract_lattice_s(l, rem_args)
end

function Base.show(io::IO, ::MIME"text/plain", lv::LatticeValueWrapper)
    print(io, "LatticeValue{$(eltype(lv))} on a ")
    summary(io, lattice(lv))
    if !requires_compact(io)
        print(io, "\nValues stored in a $(typeof(lv.values)):\n")
        Base.show_vector(IOContext(io, :compact => true), lv.values)
    end
end

site_inds(l::AbstractLattice{SiteT}, lv_mask::LatticeValue{Bool, <:AbstractLattice{SiteT}}) where SiteT<:AbstractSite =
    Int[site_index(l, lattice(lv_mask)[i])
        for i in eachindex(lv_mask.values) if lv_mask.values[i]]
Base.@propagate_inbounds function Base.getindex(l::AbstractLattice, lv_mask::LatticeValue{Bool})
    @boundscheck check_issublattice(lattice(lv_mask), l)
    inds = site_inds(l, lv_mask)
    l[inds]
end

Base.@propagate_inbounds function Base.getindex(lv::LatticeValueWrapper, lv_mask::LatticeValue{Bool})
    @boundscheck check_samelattice(lv, lv_mask)
    inds = site_inds(lattice(lv), lv_mask)
    LatticeValueWrapper(lattice(lv)[inds], lv.values[inds])
end

Base.@propagate_inbounds function Base.Broadcast.dotview(lv::LatticeValueWrapper, lv_mask::LatticeValue{Bool})
    @boundscheck check_samelattice(lv, lv_mask)
    inds = site_inds(lattice(lv), lv_mask)
    LatticeValueWrapper(lattice(lv)[inds], @view lv.values[inds])
end
function Base.Broadcast.dotview(lv::LatticeValueWrapper, pairs::Pair...; kw...)
    inds = pairs_to_indices(lattice(lv), to_param_pairs(pairs...; kw...))
    return LatticeValueWrapper(lattice(lv)[inds], @view lv.values[inds])
end

Base.@propagate_inbounds function Base.setindex!(lv::LatticeValueWrapper, lv_rhs::LatticeValueWrapper, lv_mask::LatticeValue{Bool})
    @boundscheck begin
        check_issublattice(lattice(lv_mask), lattice(lv))
        check_issublattice(lattice(lv_rhs), lattice(lv))
    end
    inds_l = site_inds(lattice(lv), lv_mask)
    inds_r = site_inds(lattice(lv_rhs), lv_mask)
    lv.values[inds_l] = @view lv_rhs.values[inds_r]
    return lv_rhs
end

function Base.getindex(lvw::LatticeValueWrapper, pairs::Pair...; kw...)
    inds = pairs_to_indices(lattice(lvw), to_param_pairs(pairs...; kw...))
    return length(inds) == 1 ? lvw.values[only(inds)] :
        LatticeValueWrapper(lattice(lvw)[inds], lvw.values[inds])
end
function Base.getindex(lvw::LatticeValueWrapper, ::typeof(!), pairs::Pair...; kw...)
    ind = pairs_to_index(lattice(lvw), to_param_pairs(pairs...; kw...))
    ind === nothing && throw(BoundsError(lvw, (pairs..., NamedTuple(kw))))
    lvw.values[ind]
end

function Base.setindex!(lv::LatticeValueWrapper, lv_rhs::LatticeValueWrapper, pairs::Pair...; kw...)
    param_pairs = to_param_pairs(pairs...; kw...)
    inds_l = pairs_to_indices(lattice(lv), param_pairs)
    inds_r = pairs_to_indices(lattice(lv_rhs), param_pairs)
    @boundscheck begin
        check_samelattice(lattice(lv)[inds_l], lattice(lv_rhs)[inds_r])
    end
    lv.values[inds_l] = @view lv_rhs.values[inds_r]
    return lv_rhs
end
function Base.setindex!(lvw::LatticeValueWrapper, rhs, ::typeof(!), pairs::Pair...; kw...)
    ind = pairs_to_index(lattice(lvw), to_param_pairs(pairs...; kw...))
    ind === nothing && throw(BoundsError(lvw, (pairs..., NamedTuple(kw))))
    lvw.values[ind] = rhs
end

"""
    project(lv, axis)

Projects the `lv::LatticeValue` along the given axis.

## Arguments
- `lv`: the `LatticeValue` to be projected.
- `axis`: the `SiteProperty` describing the axis to be projected along.
"""
function project(lv::LatticeValue, param::SiteProperty)
    pr_crds = [getsiteproperty(site, param) for site in lattice(lv)]
    perm = sortperm(pr_crds)
    pr_crds[perm], lv.values[perm]
end
project(any, param::Symbol) = project(any, SitePropertyAlias{param}())

"""
    ketstate(lv)

Converts a `LatticeValue` to a `Ket` wavefunction vector.
"""
ketstate(lv::LatticeValue) = Ket(LatticeBasis(lattice(lv)), lv.values)

"""
    brastate(lv)

Converts a `LatticeValue` to a `Bra` wavefunction vector.
"""
brastate(lv::LatticeValue) = Bra(LatticeBasis(lattice(lv)), lv.values)
QuantumOpticsBase.tensor(ket::Ket, lv::LatticeValue) = ket ⊗ ketstate(lv)
QuantumOpticsBase.tensor(bra::Bra, lv::LatticeValue) = bra ⊗ brastate(lv)
QuantumOpticsBase.tensor(lv::LatticeValue, state::QuantumOpticsBase.StateVector) = state ⊗ lv
