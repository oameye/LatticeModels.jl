"""
    LandauGauge <: AbstractField

An object representing Landau gauge uniform magnetic field along z-axis.
Fields:
- `B`: The magnetic field value
"""
struct LandauGauge <: AbstractField
    B::Float64
end
vector_potential(field::LandauGauge, p1) = (0, p1[1] * field.B)
line_integral(field::LandauGauge, p1, p2) = ((p1[1] + p2[1]) / 2) * (p2[2] - p1[2]) * field.B
Base.show(io::IO, ::MIME"text/plain", field::LandauGauge) = print(io, "Landau gauge uniform field; B = $(field.B) flux quanta per 1×1 plaquette")

"""
    SymmetricGauge <: AbstractField

An object representing symmetrically gauged uniform magnetic field along z-axis.
Fields:
- `B`: The magnetic field value
"""
struct SymmetricGauge <: AbstractField
    B::Float64
end
vector_potential(field::SymmetricGauge, p1) = SA[-p1[2], p1[1]] * field.B / 2
line_integral(field::SymmetricGauge, p1, p2) = (p1[1] * p2[2] - p2[1] * p1[2]) / 2 * field.B
Base.show(io::IO, ::MIME"text/plain", field::SymmetricGauge) =
    print(io, "Symmetric gauge uniform field; B = $(field.B) flux quanta per 1×1 plaquette")

"""
    PointFlux <: AbstractField

An object representing a small magnetic flux through given point. The field is directed along z-axis.
Fields:
- `Phi`: The magnetic flux value.
- `point`: A `Tuple` of x and y coordinates of the point.
"""
struct PointFlux <: AbstractField
    Phi::Float64
    point::NTuple{2,Float64}
    PointFlux(Phi,point=(0,0)) = new(Phi, point)
end
function vector_potential(field::PointFlux, p1)
    (x, y) = p1
    normsq = (x^2 + y^2)
    SA[-y, x] / normsq * field.Phi
end
function line_integral(field::PointFlux, p1, p2)
    Pv = SVector(field.point)
    p1 = p1[1:2] - Pv
    p2 = p2[1:2] - Pv
    if iszero(p1) || iszero(p2)
        return 0.0
    end
    asin((1 - 1e-11) * det(hcat(p1, p2)) / norm(p1) / norm(p2)) * field.Phi
end
Base.show(io::IO, ::MIME"text/plain", field::PointFlux) =
    print(io, "Delta flux field through point $(field.point); Φ = $(field.Phi) flux quanta")
