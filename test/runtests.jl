module RRRMCTest

using RRRMC
using Base.Test

function gen_timeout_hook(t = 1.0)
    t += time()
    return (it, X, C, acc, E) -> (time() ≤ t)
end

macro test_approx_eq_compat(x, y)
    return VERSION < v"0.6-" ?
        :(@test_approx_eq $(esc(x)) $(esc(y))) :
        :(@test $(esc(x)) ≈ $(esc(y)))
end

function checkenergy_hook(it, X, C, acc, E)
    @test_approx_eq_compat E RRRMC.energy(X, C)
    return true
end

function test()

    graphs = [
        RRRMC.GraphTwoSpin(),
        RRRMC.GraphThreeSpin(),
        RRRMC.GraphFields(10),
        RRRMC.GraphFields(10, (-1,1)),
        RRRMC.GraphFields(10, (-1.5,0.5)),
        RRRMC.GraphFieldsNormalDiscretized(10, (-1,0,1)),
        RRRMC.GraphFieldsNormalDiscretized(10, (-1.5,0.0,1.5)),
        RRRMC.GraphIsing1D(10),
        RRRMC.GraphPSpin3(39, 5),
        RRRMC.GraphRRG(10, 3),
        RRRMC.GraphRRG(10, 3, (-1,0,1)),
        RRRMC.GraphRRG(10, 3, (-1.0,0.0,1.0)),
        RRRMC.GraphRRG(10, 3, (-1.0,0,1)),
        RRRMC.GraphRRG(10, 3, (-1//1,0//1,1//1)),
        RRRMC.GraphRRGNormalDiscretized(10, 3, (-1,0,1)),
        RRRMC.GraphRRGNormalDiscretized(10, 3, (-1.0,0.0,1.0)),
        RRRMC.GraphRRGNormalDiscretized(10, 3, (-1.0,0,1)),
        RRRMC.GraphRRGNormalDiscretized(10, 3, (-1//1,0//1,1//1)),
        RRRMC.GraphRRGNormal(10, 3),
        RRRMC.GraphEA(2, 3),
        RRRMC.GraphEA(2, 3, (-1,0,1)),
        RRRMC.GraphEA(2, 3, (-1.0,0.0,1.0)),
        RRRMC.GraphEA(2, 3, (-1.0,0,1)),
        RRRMC.GraphEA(2, 3, (-1//1,0//1,1//1)),
        RRRMC.GraphEANormalDiscretized(2, 3, (-1,0,1)),
        RRRMC.GraphEANormalDiscretized(2, 3, (-1.0,0.0,1.0)),
        RRRMC.GraphEANormalDiscretized(2, 3, (-1.0,0,1)),
        RRRMC.GraphEANormalDiscretized(2, 3, (-1//1,0//1,1//1)),
        RRRMC.GraphEANormal(2, 3),
        RRRMC.GraphEA(3, 2),
        RRRMC.GraphEA(3, 2, (-1,0,1)),
        RRRMC.GraphEA(3, 2, (-1.0,0.0,1.0)),
        RRRMC.GraphEA(3, 2, (-1.0,0,1)),
        RRRMC.GraphEA(3, 2, (-1//1,0//1,1//1)),
        RRRMC.GraphEANormalDiscretized(3, 2, (-1,0,1)),
        RRRMC.GraphEANormalDiscretized(3, 2, (-1.0,0.0,1.0)),
        RRRMC.GraphEANormalDiscretized(3, 2, (-1.0,0,1)),
        RRRMC.GraphEANormalDiscretized(3, 2, (-1//1,0//1,1//1)),
        RRRMC.GraphEANormal(3, 2),
        RRRMC.GraphSK(10),
        RRRMC.GraphSKNormal(10),
        RRRMC.GraphQuant(10, 8, 0.5, 2.0, RRRMC.GraphEmpty, 10),
        RRRMC.GraphQuant(10, 8, 0.5, 2.0, RRRMC.GraphSK, RRRMC.SK.gen_J(10)),
        RRRMC.GraphQuant(10, 8, 0.5, 2.0, RRRMC.GraphSKNormal, RRRMC.SK.gen_J_gauss(10)),
        RRRMC.GraphQuant(3, 8, 0.5, 2.0, RRRMC.GraphThreeSpin),
        RRRMC.GraphRobustEnsemble(10, 8, 1.5, 2.0, RRRMC.GraphEmpty, 10),
        RRRMC.GraphRobustEnsemble(10, 8, 1.5, 2.0, RRRMC.GraphSK, RRRMC.SK.gen_J(10)),
        RRRMC.GraphRobustEnsemble(10, 8, 1.5, 2.0, RRRMC.GraphSKNormal, RRRMC.SK.gen_J_gauss(10)),
        RRRMC.GraphRobustEnsemble(3, 8, 1.5, 2.0, RRRMC.GraphThreeSpin),
        RRRMC.GraphLocalEntropy(10, 8, 1.5, 2.0, RRRMC.GraphEmpty, 10),
        RRRMC.GraphLocalEntropy(10, 8, 1.5, 2.0, RRRMC.GraphSKNormal, RRRMC.SK.gen_J_gauss(10)),
        RRRMC.GraphLocalEntropy(3, 8, 1.5, 2.0, RRRMC.GraphThreeSpin),
        RRRMC.GraphRobustEnsemble(20, 4, 1.5, 2.0, RRRMC.GraphQuant, 5, 4, 0.5, 2.0, RRRMC.GraphSK, RRRMC.SK.gen_J(5)),
       ]

    β = 2.0
    iters = 10_000
    st = 100
    samples = iters ÷ st

    for X in graphs
        E, C = standardMC(X, β, iters, step=st)
        E, C = standardMC(X, β, iters, step=st, C0=C, hook=checkenergy_hook)
        E, C = standardMC(X, β, iters, step=st, C0=C, hook=gen_timeout_hook())

        E, C = bklMC(X, β, iters, step=st)
        E, C = bklMC(X, β, iters, step=st, C0=C, hook=checkenergy_hook)
        E, C = bklMC(X, β, iters, step=st, C0=C, hook=gen_timeout_hook())

        E, C = wtmMC(X, β, samples, step=Float64(st))
        E, C = wtmMC(X, β, samples, step=Float64(st), C0=C, hook=checkenergy_hook)
        E, C = wtmMC(X, β, samples, step=Float64(st), C0=C, hook=gen_timeout_hook())

        E, C = rrrMC(X, β, iters, step=st)
        E, C = rrrMC(X, β, iters, step=st, C0=C, hook=checkenergy_hook)
        E, C = rrrMC(X, β, iters, step=st, C0=C, hook=gen_timeout_hook())
        E, C = rrrMC(X, β, iters, step=st, staged_thr=0.0, hook=checkenergy_hook)
        E, C = rrrMC(X, β, iters, step=st, C0=C, staged_thr=0.0)
        E, C = rrrMC(X, β, iters, step=st, staged_thr=1.0, hook=checkenergy_hook)
        E, C = rrrMC(X, β, iters, step=st, C0=C, staged_thr=1.0)

        if isa(X, RRRMC.DoubleGraph)
            X0 = RRRMC.inner_graph(X)
            E, C = bklMC(X0, β, iters, step=st)
            E, C = bklMC(X0, β, iters, step=st, C0=C, hook=checkenergy_hook)

            E, C = rrrMC(X, β, iters, step=st)
            E, C = rrrMC(X, β, iters, step=st, C0=C, hook=checkenergy_hook)
            E, C = rrrMC(X, β, iters, step=st, C0=C, hook=gen_timeout_hook())
            E, C = rrrMC(X, β, iters, step=st, staged_thr=0.0, hook=checkenergy_hook)
            E, C = rrrMC(X, β, iters, step=st, C0=C, staged_thr=0.0)
            E, C = rrrMC(X, β, iters, step=st, staged_thr=1.0, hook=checkenergy_hook)
            E, C = rrrMC(X, β, iters, step=st, C0=C, staged_thr=1.0)


            E, C = rrrMC(X0, β, iters, step=st)
            E, C = rrrMC(X0, β, iters, step=st, C0=C, hook=checkenergy_hook)
            E, C = rrrMC(X0, β, iters, step=st, C0=C, hook=gen_timeout_hook())
            E, C = rrrMC(X0, β, iters, step=st, staged_thr=0.0, hook=checkenergy_hook)
            E, C = rrrMC(X0, β, iters, step=st, C0=C, staged_thr=0.0)
            E, C = rrrMC(X0, β, iters, step=st, staged_thr=1.0, hook=checkenergy_hook)
            E, C = rrrMC(X0, β, iters, step=st, C0=C, staged_thr=1.0)
        end
    end
end

test()

end # module
