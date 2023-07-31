using Test, LinearAlgebra, StaticArrays, Plots
using LatticeModels

@static if VERSION < v"1.8"
    # Ignore test_throws
    macro test_throws(args...)
        :()
    end
end

@testset "Workflows" begin
    @test begin
        l = SquareLattice(10, 10) do (x, y)
            √(x^2 + y^2) < 5
        end
        b = LatticeBasis(l)
        d = identityoperator(b)
        hx = hoppings(l, Bonds(axis=1))
        hy = hoppings(l, Bonds(axis=2))
        H = d + hx + hy
        eig = diagonalize(H)
        P = densitymatrix(eig, statistics=FermiDirac)
        all(isfinite, P.data)
    end

    @test begin
        l = HoneycombLattice(10, 10)
        H = haldane(l, 1, 1, 1)
        P = densitymatrix(diagonalize(H), statistics=FermiDirac)
        X, Y = coord_operators(basis(H))
        d = site_density(4π * im * P * X * (one(P) - P) * Y * P)
        rd = d .|> real
        true
    end

    @test begin
        l = SquareLattice(10, 10)
        spin = SpinBasis(1//2)
        phasespace = l ⊗ spin
        H0 = build_hamiltonian(phasespace,
            [1 0; 0 -1] => rand(l),
            [1 im; im -1] / 2 => Bonds(axis = 1),
            [1 1; -1 -1] / 2 => Bonds(axis = 2),
            field = LandauField(0.5)
        )
        function h(t)
            x, y = coord_values(l)
            ms = @. 3 + (√(x^2 + y^2) ≤ 2) * -2
            build_hamiltonian(l, spin,
                sigmaz(spin) => ms,
                randn(l),
                [1 im; im -1] / 2 => Bonds(axis = 1),
                [1 1; -1 -1] / 2 => Bonds(axis = 2),
                field = LandauField(t)
            )
        end
        P0 = densitymatrix(diagonalize(H0), statistics=FermiDirac)
        X, Y = coord_operators(basis(H0))
        @evolution {H := h(t), P0 --> H --> P} for t in 0:0.1:10
            d = site_density(4π * im * P * X * (one(P) - P) * Y * P)
            ch = materialize(DensityCurrents(H, P))
            rd = d .|> real
        end
        true
    end

    @test begin
        l = SquareLattice(10, 10)
        spin = SpinBasis(1//2)
        X, Y = coord_operators(l)
        x, y = coord_values(l)
        xy = x .* y
        p = plot(layout=4)
        plot!(p[1], xy)
        H = build_hamiltonian(l, spin,
            sigmaz(spin),
            [1 im; im -1] / 2 => Bonds(axis = 1),
            [1 1; -1 -1] / 2 => Bonds(axis = 2),
            field = LandauField(0.5)
        )
        P = densitymatrix(diagonalize(H), μ = 0.1, statistics=FermiDirac)
        @evolution k = 2 pade = true {P --> H --> PP} for t in 0:0.1:1
        end
        @evolution k = 2 {P --> H --> PP} for t in 0:0.1:1
        end

        dc = DensityCurrents(H, P)
        quiver!(p[1], dc[x.<y])
        scatter!(p[1], l)
        scatter!(p[1], l[x.<y], high_contrast=true)
        scatter!(p[1], xy[x.≥y])
        plot!(p[1], adjacency_matrix(H))
        plot!(p[1], adjacency_matrix(l, Bonds([1, 1])))
        surface!(p[2], xy)
        scatter!(p[3], SquareLattice(3, 4, 5))
        plot!(p[4], project(xy, :x))
        plot!(p[4], project(xy, :j1))
        mpcs = map_currents(site_distance, dc, reduce_fn=sum, sort=true)
        plot!(p[4], mpcs)
        true
    end
end

@testset "Lattice" begin
    sql = SquareLattice(10, 20)
    @test [site_index(sql, s) for s in sql] == 1:length(sql)
    x, y = coord_values(sql)
    s_0 = SquareLattice(10, 20) do (x, y)
        x < y
    end
    s_1 = sublattice(sql) do (x, y)
        x < y
    end
    s_2 = sql[x.<y]
    @test s_0 == s_1
    @test s_1 == s_2

    hl = HoneycombLattice(10, 10)
    xh, yh = coord_values(hl)
    s_3 = HoneycombLattice(10, 10) do (x, y)
        x < y
    end
    s_4 = sublattice(hl) do (x, y)
        x < y
    end
    s_5 = hl[xh.<yh]
    @test s_3 == s_4
    @test s_4 == s_5
    @test_throws MethodError hl[x.<y]
    @test hl[j1=3, j2=2, index=1] == LatticeModels.LatticeSite(
        LatticeModels.LatticePointer(SA[3, 2], 1), SA[4.0, 1.7320508075688772])
    xb, yb = coord_values(SquareLattice(5, 40))
    @test_throws "macrocell mismatch" sql[xb.<yb]
    sql2 = sublattice(sql) do site
        site ∉ (sql[1], sql[end])
    end
    pop!(sql)
    popfirst!(sql)
    @test sql == sql2
end

@testset "LatticeValue" begin
    l = SquareLattice(2, 2)
    x, y = coord_values(l)
    @test x.values == [1, 2, 1, 2]
    @test y.values == [1, 1, 2, 2]
    l = SquareLattice(10, 10)
    bas = LatticeBasis(l)
    X, Y = coord_operators(bas)
    x, y = coord_values(l)
    xtr = diag_reduce(tr, X)
    xtr2 = site_density(X)
    xm2 = LatticeValue(l) do (x, y)
        2x
    end
    y = LatticeValue(l) do (x, y)
        y
    end
    xy = LatticeValue(l) do site
        site.x * site.y
    end
    idxs = LatticeValue(l) do site
        site_index(l, site)
    end
    @test [idxs[s] for s in l] == 1:length(l)
    @test x == xtr
    @test x == xtr2
    @testset "Broadcast" begin
        @test x .* y == xy
        @test x .* 2 == xm2
        @test 2 .* x == xm2
        @test x .|> (x -> 2x) == xm2
        y .= x .* y
        @test y == xy
        @test_throws "cannot broadcast" x .* ones(100)
        l2 = SquareLattice(5, 20)
        x2 = LatticeValue(l2) do (x, y)
            x
        end
        @test_throws "lattice mismatch" x .* x2
    end
    @testset "Indexing" begin
        z = zeros(l)
        z2 = zero(z)
        z .= 1
        z2[x.≥y] .+= 1
        z2[x.<y] = ones(l)
        @test z == ones(l)
        @test z2 == ones(l)
        @test z[x=1, x2=1] == 1
        z3 = ones(l)
        for i in 2:10
            z3[x1=i] .= i
        end
        @test z3 == x
    end
    @testset "Interface" begin
        (mn, i) = findmin(xy)
        (mx, j) = findmax(xy)
        @test xy[i] == mn
        @test xy[j] == mx
        @test all(mn .≤ xy.values .≤ mx)
        imx = findall(==(mx), xy)
        @test all((site in imx || xy[site] < mx) for site in l)
    end
end

@testset "TimeSequence" begin
    l = SquareLattice(3, 3)
    site = l[5]
    x, y = coord_values(l)
    xy = x .* y
    xly = x .< y
    @test_throws "length mismatch" TimeSequence([0.5], [xy, xy])
    rec = TimeSequence{LatticeValue}()
    insert!(rec, 0, xy)
    insert!(rec, 1, xy)
    insert!(rec, 2, xy)
    @test rec[site] == TimeSequence(time_domain(rec), fill(xy[site], 3))
    @test rec[xly] == TimeSequence(0:2, fill(xy[xly], 3))
    @test collect(rec) == [0 => xy, 1 => xy, 2 => xy]
    @test differentiate(rec) == TimeSequence([0.5, 1.5], [zeros(l), zeros(l)])
    @test differentiate(rec[site]) == TimeSequence([0.5, 1.5], [0, 0])
    rec2 = TimeSequence(xy .* 0)
    insert!(rec2, 1, xy .* 1)
    insert!(rec2, 2, xy .* 2)
    @test rec2(0.9) == xy
    @test rec2(0.9, 2.1) == TimeSequence([1, 2], [xy, xy .* 2])
    @test integrate(rec) == rec2
end

@testset "Bonds" begin
    @testset "Constructor" begin
        @test Bonds(axis=1) == Bonds([1])
        @test Bonds(axis=1) != Bonds([1, 0])
        @test_throws "connects site to itself" Bonds(2 => 2, [0, 0])
    end
    @testset "Hopping matching" begin
        l = SquareLattice(6, 5)
        hx = Bonds(axis=1)
        hxmy = Bonds([1, -1])
        pbc = BoundaryConditions(1 => true)
        for site in l
            ucx, ucy = site.unit_cell
            dst_dx = LatticeModels.shift_site(BoundaryConditions(), l, site + hx)[2]
            dst_dxmy = LatticeModels.shift_site(pbc, l, site + hxmy)[2]
            @test !(dst_dx in l) == (ucx == 6)
            @test !(dst_dxmy in l) == (ucy == 1)
        end
    end
    @testset "Bonds" begin
        l = SquareLattice(2, 2)
        ls1, _, ls3, ls4 = l
        bs = adjacency_matrix(l, Bonds(axis=1), Bonds(axis=2))
        bs1 = adjacency_matrix(l, Bonds(axis=1)) | adjacency_matrix(l, Bonds(axis=2))
        bs2 = bs^2
        @test bs.bmat == (!!bs).bmat
        @test bs.bmat == bs1.bmat
        @test LatticeModels.match(bs, ls1, ls3)
        @test !LatticeModels.match(bs, ls1, ls4)
        @test LatticeModels.match(bs2, ls1, ls3)
        @test LatticeModels.match(bs2, ls1, ls4)
    end
    l = SquareLattice(5, 5) do site
        local (x, y) = site.coords
        abs(x + y) < 2.5
    end
    x, y = coord_values(l)
    op1 = hoppings(PairLhsGraph(x .< y), l, Bonds(axis=1))
    op2 = hoppings(l, Bonds(axis=1)) do l, site1, site2
        local (x, y) = site1.coords
        x < y
    end
    @test op1 == op2
end

@testset "Field" begin
    struct LazyLandauField <: LatticeModels.AbstractField
        B::Number
    end
    LatticeModels.vector_potential(field::LazyLandauField, p1) = (0, p1[1] * field.B)
    struct StrangeLandauField <: LatticeModels.AbstractField end
    LatticeModels.vector_potential(::StrangeLandauField, point) = (0, point[1] * 0.1)
    LatticeModels.line_integral(::StrangeLandauField, p1, p2) = 123
    struct EmptyField <: LatticeModels.AbstractField end
    l = SquareLattice(10, 10)
    la = LandauField(0.1)
    lla = LazyLandauField(0.1)
    sla = StrangeLandauField()
    sym = SymmetricField(0.1)
    flx = FluxField(0.1)
    flx2 = FluxField(0.1, (0, 0))
    @test flx.P == flx2.P
    emf = EmptyField()
    fla = MagneticField() do (x,)
        (0, x * 0.1)
    end
    @testset "Path integral" begin
        p1 = SA[1, 2]
        p2 = SA[3, 4]
        @test LatticeModels.line_integral(la, p1, p2) ≈
              LatticeModels.line_integral(la, p1, p2, 100)
        @test LatticeModels.line_integral(lla, p1, p2) ≈
              LatticeModels.line_integral(lla, p1, p2, 100)
        @test LatticeModels.line_integral(la, p1, p2) ≈
              LatticeModels.line_integral(lla, p1, p2)
        @test LatticeModels.line_integral(la, p1, p2) ≈
              LatticeModels.line_integral(fla, p1, p2)

        @test LatticeModels.line_integral(sla, p1, p2, 100) ≈
              LatticeModels.line_integral(la, p1, p2)
        @test LatticeModels.line_integral(sla, p1, p2) == 123

        @test LatticeModels.line_integral(sym, p1, p2, 1) ≈
              LatticeModels.line_integral(sym, p1, p2)
        @test LatticeModels.line_integral(sym, p1, p2, 100) ≈
              LatticeModels.line_integral(sym, p1, p2)

        @test LatticeModels.line_integral(flx, p1, p2, 1000) ≈
              LatticeModels.line_integral(flx, p1, p2) atol = 1e-8
        @test LatticeModels.line_integral(flx + sym, p1, p2, 1000) ≈
              LatticeModels.line_integral(flx + sym, p1, p2) atol = 1e-8

        @test_throws "no vector potential function" LatticeModels.vector_potential(emf, SA[1, 2, 3])
    end

    @testset "Field application" begin
        H1 = hoppings(l, Bonds(axis=1), Bonds(axis = 2), field = la)
        H2 = hoppings(l, Bonds(axis=1), Bonds(axis=2), field = lla)
        H3 = hoppings(l, Bonds(axis=1), Bonds(axis=2))
        H4 = copy(H3)
        apply_field!(H3, la)
        apply_field!(H4, lla)
        @test H1 ≈ H2
        @test H2 ≈ H3
        @test H3 ≈ H4
    end
end

@testset "Hamiltonian" begin
    @testset "Operator builder" begin
        l = SquareLattice(10, 10)
        spin = SpinBasis(1//2)
        builder = OperatorBuilder(l ⊗ spin)
        @increment for site in l
            builder[site, site] += sigmaz(spin)

            site_hx = site + SiteOffset(axis = 1)
            builder[site, site_hx] += (sigmaz(spin) - im * sigmax(spin)) / 2
            builder[site_hx, site] += (sigmaz(spin) + im * sigmax(spin)) / 2

            site_hy = site + SiteOffset(axis = 2)
            builder[site, site_hy] += (sigmaz(spin) - im * sigmay(spin)) / 2
            builder[site_hy, site] += (sigmaz(spin) + im * sigmay(spin)) / 2
        end
        H1 = to_operator(builder)
        H2 = qwz(l)
        @test H1 == H2
    end

    @testset "DOS & LDOS" begin
        sp = diagonalize(qwz(ones(SquareLattice(10, 10))))
        E = 2
        δ = 0.2
        Es = sp.values
        Vs = sp.states
        ld1 = imag.(diag_reduce(tr, Operator(basis(sp), Vs * (@.(1 / (Es - E - im * δ)) .* Vs'))))
        ldosf = ldos(sp, δ)
        @test ldos(sp, E, δ).values ≈ ld1.values
        @test ldosf(E).values ≈ ld1.values
        @test dos(sp, δ)(E) ≈ sum(ld1)
    end
end

@testset "Currents" begin
    l = SquareLattice(10, 10)
    x, y = coord_values(l)
    H(B) = qwz(l, field=LandauField(B))
    P = densitymatrix(diagonalize(H(0)), statistics=FermiDirac)
    dc = DensityCurrents(H(0.1), P)
    bs = adjacency_matrix(H(0.1))
    m1 = materialize(dc)[x.<y]
    m2 = materialize(dc[x.<y])
    m3 = materialize(bs, dc)[x.<y]
    m4 = materialize(bs, dc[x.<y])
    md = materialize(pairs_by_distance(≤(2)), dc[x.<y])
    @test m1.currents == m2.currents
    @test m1.currents == m3.currents
    @test m1.currents == m4.currents
    @test m1.currents == md.currents
    @test (m1 + m2 - m3).currents ≈ (2 * m4 * 1 - md / 1).currents
    s1 = l[23]
    s2 = l[45]
    @test dc[s1, s2] == -dc[s2, s1]
    @test abs(dc[s1, s1]) < eps()
end
