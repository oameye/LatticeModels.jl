import QuantumOpticsBase: DataOperator

function add_diagonal!(builder, op, diag)
    for i in 1:length(diag)
        increment!(builder, op, i, i, factor=diag[CartesianIndex(i)])
    end
end

@inline _get_bool_value(::Nothing, ::Lattice, ::LatticeSite, ::LatticeSite) = true
@inline _get_bool_value(f::Function, l::Lattice, site1::LatticeSite, site2::LatticeSite) =
    f(l, site1, site2)
@inline _get_bool_value(g::AbstractGraph, ::Lattice, site1::LatticeSite, site2::LatticeSite) =
    match(g, site1, site2)

function add_hoppings!(builder, selector, l::Lattice, op, bond::SiteOffset,
        field::AbstractField, boundaries::AbstractBoundaryConditions)
    dims(bond) > dims(l) && error("Incompatible dims")
    trv = radius_vector(l, bond)
    for site1 in l
        lp = site1 + bond
        lp === nothing && continue
        add_hoppings!(builder, selector, l, op, site1 => LatticeSite(lp, site1.coords + trv), field, boundaries)
    end
end

function add_hoppings!(builder, selector, l::Lattice, op, bond::SingleBond,
        field::AbstractField, boundaries::AbstractBoundaryConditions)
    site1, site2 = bond
    p1 = site1.coords
    p2 = site2.coords
    factor, site2 = shift_site(boundaries, l, site2)
    i = @inline site_index(l, site1)
    j = @inline site_index(l, site2)
    i === nothing && return
    j === nothing && return
    !_get_bool_value(selector, l, site1, site2) && return
    total_factor = exp(-2π * im * line_integral(field, p1, p2)) * factor
    !isfinite(total_factor) && error("got NaN or Inf when finding the phase factor")
    increment!(builder, op, i, j, factor=total_factor)
    increment!(builder, op', j, i, factor=total_factor')
end

struct Hamiltonian{SystemT, BasisT, T} <: DataOperator{BasisT, BasisT}
    sys::SystemT
    basis_l::BasisT
    basis_r::BasisT
    data::T
end
function Hamiltonian(sys::System, op::Operator)
    return Hamiltonian(sys, basis(op), basis(op), op.data)
end
QuantumOpticsBase.Operator(ham::Hamiltonian) = Operator(ham.basis_l, ham.data)
system(::DataOperator) = nothing
system(ham::Hamiltonian) = ham.sys
Base.:(*)(op::Operator{B1, B2}, ham::Hamiltonian{Sys, B2}) where{Sys, B1, B2} = op * Operator(ham)
Base.:(*)(ham::Hamiltonian{Sys, B2}, op::Operator{B1, B2}) where{Sys, B1, B2} = Operator(ham) * op
Base.:(+)(op::Operator{B, B}, ham::Hamiltonian{Sys, B}) where{Sys, B} = op + Operator(ham)
Base.:(+)(ham::Hamiltonian{Sys, B}, op::Operator{B, B}) where{Sys, B} = Operator(ham) + op

function tightbinding_hamiltonian(sys::System; t1=1, t2=0, t3=0,
    field=NoField(), boundaries=BoundaryConditions())
    sample = sys.sample
    l = lattice(sys)
    builder = SparseMatrixBuilder{ComplexF64}(length(sys), length(sys))
    internal_eye = internal_one(sample)
    for bond in default_bonds(l)
        add_hoppings!(builder, nothing, l, t1 * internal_eye, bond, field, boundaries)
    end
    if t2 != 0
        for bond in default_bonds(l, Val(2))
            add_hoppings!(builder, nothing, l, t2 * internal_eye, bond, field, boundaries)
        end
    end
    if t3 != 0
        for bond in default_bonds(l, Val(3))
            add_hoppings!(builder, nothing, l, t3 * internal_eye, bond, field, boundaries)
        end
    end
    return Hamiltonian(sys, manybodyoperator(sys, to_matrix(builder)))
end
@accepts_system tightbinding_hamiltonian

const AbstractSiteOffset = Union{SiteOffset, SingleBond}
function build_operator!(builder::SparseMatrixBuilder, sample::Sample, arg::Pair{<:Any, <:Tuple}; kw...)
    opdata, bonds = arg
    for bond in bonds
        build_operator!(builder, sample, opdata => bond; kw...)
    end
end
function build_operator!(builder::SparseMatrixBuilder, sample::Sample, arg::Pair{<:Any, <:AbstractSiteOffset};
        field=NoField())
    # Hopping operator
    opdata, bond = arg
    add_hoppings!(builder, sample.adjacency_matrix, sample.latt, opdata, bond, field, sample.boundaries)
end
function build_operator!(builder::SparseMatrixBuilder, sample::Sample, arg::Pair{<:Any, <:LatticeValue}; kw...)
    # Diagonal operator
    opdata, lv = arg
    add_diagonal!(builder, opdata, lv.values)
end
function build_operator!(builder::SparseMatrixBuilder, ::Sample, arg::DataOperator; kw...)
    # Arbitrary sparse operator
    increment!(builder, arg.data)
end

function preprocess_argument(sample::Sample, arg::DataOperator)
    if samebases(basis(arg), basis(sample))
        sparse(arg)
    elseif samebases(basis(arg), sample.internal)
        sparse(arg) ⊗ one(LatticeBasis(sample.latt))
    elseif samebases(basis(arg), LatticeBasis(sample.latt))
        internal_one(sample) ⊗ sparse(arg)
    else
        error("Invalid Operator argument: basis does not match neither lattice nor internal phase space")
    end
end

function preprocess_argument(sample::Sample, arg::AbstractMatrix)
    bas = sample.internal
    if all(==(length(bas)), size(arg))
        preprocess_argument(sample, SparseOperator(bas, arg))
    else
        error("Invalid Matrix argument: size does not match on-site dimension count")
    end
end

preprocess_argument(sample::Sample, arg) =
    preprocess_argument(sample, internal_one(sample) => arg)

preprocess_argument(sample::Sample, n::Number) = preprocess_argument(sample, n * internal_one(sample))

function preprocess_argument(sample::Sample, arg::Pair)
    op, on_lattice = arg
    if op isa Operator
        check_samebases(basis(op), sample.internal)
        opdata = sparse(op.data)
    elseif op isa AbstractMatrix
        opdata = sparse(op)
    elseif op isa Number
        opdata = op
    else
        error("Invalid Pair argument: unsupported on-site operator type")
    end
    if on_lattice isa LatticeValue
        check_samelattice(on_lattice, sample)
        return opdata => on_lattice
    elseif on_lattice isa Number
        return preprocess_argument(sample, opdata * on_lattice)
    elseif on_lattice isa AbstractSiteOffset
        return opdata => on_lattice
    else
        error("Invalid Pair argument: unsupported on-lattice operator type")
    end
end

function build_hamiltonian(sys::System, args...;
        field=NoField())
    sample = sys.sample
    builder = SparseMatrixBuilder{ComplexF64}(length(sample), length(sample))
    for arg in args
        build_operator!(builder, sample, preprocess_argument(sample, arg);
            field=field)
    end
    op = Operator(basis(sample), to_matrix(builder))
    return Hamiltonian(sys, manybodyoperator(sys, op))
end
@accepts_system build_hamiltonian

hoppings(adj, l::Lattice, bs::SiteOffset...; kw...) = Operator(build_hamiltonian(Sample(adj, l), bs...; kw...))
hoppings(l::Lattice, bs::SiteOffset...; kw...) = Operator(build_hamiltonian(Sample(l), bs...; kw...))
