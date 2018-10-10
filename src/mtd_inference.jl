# mtd.jl

export ParamsMTD, PriorMTD, ModMTD,
  sim_mtd, symmetricDirPrior_mtd, transTensor_mtd,
  rpost_lλ_mtd, counttrans_mtd, rpost_lQ_mtd,
  rpost_ζ_mtd, rpost_ζ_mtd_marg, MetropIndep_λζ, mcmc_mtd!; # remove the inner functions after testing

mutable struct ParamsMTD
  lλ::Vector{Float64}
  ζ::Vector{Int} # will be length TT - R
  lQ::Matrix{Float64} # organized so first index is now and lag 1 is the next index
end

mutable struct PriorMTD
  λ::Union{Vector{Float64}, SparseDirMixPrior, SparseSBPrior, SparseSBPriorP, SparseSBPriorFull}
  Q::Union{Matrix{Float64}, Vector{SparseDirMixPrior}, Vector{SparseSBPrior}, Vector{SparseSBPriorP}}
end

mutable struct ModMTD
  R::Int # maximal order
  K::Int # number of states
  TT::Int
  S::Vector{Int}
  prior::PriorMTD
  state::ParamsMTD
  λ_indx::Tuple
  iter::Int

  ModMMTD(R, K, TT, S, prior, state, λ_indx) = new(R, K, TT, S, prior, state, λ_indx, 0)
end

## Keep around for compatibility with old simulations
# mutable struct PostSimsMMTD
#   Λ::Matrix{Float64}
#   λ::Array{Matrix{Float64}}
#   Q::Array{Matrix{Float64}}
#   Z::Matrix{Int}
#   ζ::Array{Matrix{Int}}
#   p1::Matrix{Float64}
#
#   PostSimsMMTD(Λ, λ, Q, Z, ζ) = new(Λ, λ, Q, Z, ζ, nothing)
#   PostSimsMMTD(Λ, λ, Q, Z, ζ, p1) = new(Λ, λ, Q, Z, ζ, p1)
# end

mutable struct PostSimsMTD
  λ::Matrix{Float64}
  Q::Array{Matrix{Float64}}
  ζ::Matrix{Int}
  p1λ::Vector{Float64} # SBM π
  p1Q::Matrix{Float64} # SBM π

  # PostSimsMMTD(Λ, λ, Q, Z, ζ) = new(Λ, λ, Q, Z, ζ, nothing, nothing)
  # PostSimsMMTD(Λ, λ, Q, Z, ζ, p1λ) = new(Λ, λ, Q, Z, ζ, p1λ, nothing)
  # PostSimsMMTD(Λ, λ, Q, Z, ζ, p1Q) = new(Λ, λ, Q, Z, ζ, nothing, p1Q)
  PostSimsMMTD(λ, Q, ζ, p1λ, p1Q) = new(λ, Q, ζ, p1λ, p1Q)
end


"""
    sim_mtd(TT, nburn, R, K, λ, Q)
"""
function sim_mtd(TT::Int, nburn::Int, R::Int, K::Int,
  λ::Vector{Float64}, Q#=::Array{Array{Float64}}=#)

  Nsim = nburn + TT

  ζ = [ StatsBase.sample(Weights(λ[m])) for i in 1:(Nsim-R) ]

  S = Vector{Int}(undef, Nsim)
  S[1:R] = StatsBase.sample(1:K, R)

  for tt in (R+1):(Nsim)
    i = tt - R
    Slagrev_now = S[range(tt-1, step=-1, length=R)]
    pvec = copy( Q[:, Slagrev_now[ζ[i]] ] )
    S[tt] = StatsBase.sample(Weights( pvec ))
  end

  S[(nburn+1):(Nsim)], ζ[(nburn+1):(Nsim-R)]
end


"""
    symmetricPrior_mtd(size_λ, size_Q, R, K)
"""
function symmetricDirPrior_mtd(size_λ::Float64, size_Q::Float64,
  R::Int, K::Int)

  α0_λ = fill( size_λ / float(R), R )
  a0_Q = size_Q / float(K)
  α0_Q = fill( a0_Q, (K, K) )

  (α0_λ, α0_Q)
end


"""
    transTensor_mtd(R, K, λ, Q)

Calculate full transition tensor from λ and Q.
"""
function transTensor_mtd(R::Int, K::Int, λ::Vector{Float64}, Q#=::Vector{Array{Float64}}=#)

    froms, nfroms = create_froms(K, R) # in this case, ordered by now, lag1, lag2, etc.
    Ωmat = zeros(Float64, (K, nfroms))
    for i in 1:nfroms
        for k in 1:K
            for ℓ in 1:R
                Ωmat[k,i] += λ[ℓ] .* Q[k,froms[i][ℓ]]
            end
        end
    end
    reshape(Ωmat, fill(K,R+1)...)
end

"""
    rpost_lλ_mtd(α0_λ, ζ, R)
"""
function rpost_lλ_mtd(α0_λ::Vector{Float64}, ζ::Vector{Int}, R::Int)

    Nζ = StatsBase.counts(ζ, 1:R)
    α1_λ = α0_λ .+ Nζ
    lλ_out = SparseProbVec.rDirichlet(α1_λ, true)

    lλ_out
end
function rpost_lλ_mtd(prior::SparseDirMixPrior, ζ::Vector{Int}, R::Int)

    Nζ = StatsBase.counts(ζ, 1:R)
    α1_λ = prior.α .+ Nζ
    lλ_out = SparseProbVec.rSparseDirMix(α1_λ, prior.β, true)

    lλ_out
end
function rpost_lλ_mtd(prior::SparseSBPrior, ζ::Vector{Int}, R::Int)

    Nζ = StatsBase.counts(ζ, 1:R)
    lw_now, z_now, ξ_now = SparseProbVec.rpost_sparseStickBreak(Nζ,
        prior.p1, prior.η, prior.μ, prior.M, true )

    lλ_out = copy(lw_now)

    lλ_out
end
function rpost_lλ_mtd!(prior::SparseSBPriorP, ζ::Vector{Int}, R::Int)

    Nζ = StatsBase.counts(ζ, 1:R)
    lw_now, z_now, ξ_now, prior.p1_now = SparseProbVec.rpost_sparseStickBreak(Nζ,
        prior.p1_now, prior.η, prior.μ, prior.M, prior.a_p1, prior.b_p1, true)

    lλ_out = copy(lw_now)

    lλ_out
end
function rpost_lλ_mtd!(prior::SparseSBPriorFull, ζ::Vector{Int}, R::Int)

    Nζ = StatsBase.counts(ζ, 1:R)
    lw_now, z_now, ξ_now, prior.μ_now, prior.p1_now = SparseProbVec.rpost_sparseStickBreak(Nζ,
        prior.p1_now, prior.η, prior.μ_now, prior.M,
        prior.a_p1, prior.b_p1, prior.a_μ, prior.b_μ, true)

    lλ_out = copy(lw_now)

  lλ_out
end


"""
    counttrans_mtd(S, TT, ζ, R, K)

    ### Example
    ```julia
    R = 2
    K = 3
    TT = 12
    S = [1,2,1,3,3,1,2,1,3,2,1,1]
    ζ = [1,2,1,2,1,2,1,2,1,2]
      counttrans_mtd(S, TT, ζ, R, K)
    ```
"""
function counttrans_mtd(S::Vector{Int}, TT::Int, ζ::Vector{Int},
  R::Int, K::Int)

  ## initialize
  N_out = zeros(Int, (K,K))

  ## pass through data and add counts
  for tt in (R+1):(TT)
    Slagrev_now = copy( S[range(tt-1, step=-1, length=R)] )
    from = copy( Slagrev_now[ ζ[tt-R] ] )
    N_out[ S[tt], from ] += 1
  end

  N_out
end

"""
    rpost_lQ_mmtd(S, TT, prior, ζ, R, K)
"""
function rpost_lQ_mtd(S::Vector{Int}, TT::Int, prior::Matrix{Float64},
    ζ::Vector{Int}, R::Int, K::Int)

    ## initialize
    α0_Q = copy(prior)
    lQ_out = Matrix{Float64}(undef, K, K)

    N = counttrans_mtd(S, TT, ζ, R, K)

    α1_Q = α0_Q .+ N
    for j in 1:K
        lQ_out[:,j] = SparseProbVec.rDirichlet(α1_Q[:,j], true)
    end

    lQ_out
end
function rpost_lQ_mtd(S::Vector{Int}, TT::Int,
    prior::Vector{SparseDirMixPrior},
    ζ::Vector{Int}, R::Int, K::Int)

    ## initialize
    lQ_out = Matrix{Float64}(undef, K, K)

    N = counttrans_mtd(S, TT, ζ, R, K)

    for j in 1:K
        α1 = prior[j].α .+ N[:,j]
        lQ_out[:,j] = SparseProbVec.rSparseDirMix(α1, prior[j].β, true)
    end

    lQ_out
end
function rpost_lQ_mtd(S::Vector{Int}, TT::Int,
    prior::Vector{SparseSBPrior}, ζ::Vector{Int},
    R::Int, K::Int)

    ## initialize
    lQ_out = Matrix{Float64}(undef, K, K)

    N = counttrans_mtd(S, TT, ζ, R, K)

    for j in 1:K
        lQ_out[:,j] = SparseProbVec.rpost_sparseStickBreak(N[:,j],
            prior[j].p1, prior[j].η, prior[j].μ, prior[j].M, true)[1]
    end

    lQ_out
end
function rpost_lQ_mtd!(S::Vector{Int}, TT::Int, prior::Vector{SparseSBPriorP},
    ζ::Matrix{Int}, R::Int, K::Int)

    ## initialize
    lQ_out = Matrix{Float64}(undef, K, K)

    N = counttrans_mtd(S, TT, ζ, R, K)

    for j in 1:K

        lw_now, z_now, ξ_now, p1_now = SparseProbVec.rpost_sparseStickBreak(
        N[:,j], prior[j].p1_now,
        prior[j].η, prior[j].μ, prior[j].M,
        prior[j].a_p1, prior[j].b_p1, true )

        lQ_out[:,j] = copy(lw_now)
        prior[j].p1_now = copy(p1_now)

    end

    lQ_out
end


"""
    rpost_ζ_mmtd(S, TT, lλ, lQ, R, K)
"""
function rpost_ζ_mtd(S::Vector{Int}, TT::Int,
  lλ::Vector{Float64}, lQ::Array{Float64,2},
  R::Int, K::Int)

  ζ_out = Vector{Int}(undef, TT-R)

  for i in 1:(TT-R)
      tt = i + R
      Slagrev_now = S[range(tt-1, step=-1, length=R)]
      lp = Vector{Float64}(undef, R)
      for j in 1:R
          lp[j] = lλ[j] + lQ[ append!([copy(S[tt])], copy(Slagrev_now[j]))... ]
      end

      w = exp.( lp .- maximum(lp) )
      ζ_out[i] = StatsBase.sample(Weights(w))
  end

  ζ_out
end


"""
    rpost_ζ_mtd_marg(S, ζ_old, lλ, prior_Q, TT, R, K)

    Full conditinal updates for ζ marginalizing over Q
"""
function rpost_ζ_mtd_marg(S::Vector{Int}, ζ_old::Vector{Int},
    prior_Q::Matrix{Float64},
    lλ::Vector{Float64},
    TT::Int, R::Int, K::Int)

  α0_Q = copy(prior_Q)
  ζ_out = copy(ζ_old)
  N_now = counttrans_mtd(S, TT, ζ_old, R, K) # rows are tos, cols are froms

  for i in 1:(TT-R)  # i indexes ζ, tt indexes S
    tt = i + R
    Slagrev_now = S[range(tt-1, step=-1, length=R)]
    N0 = copy(N_now)
    N0[ S[tt], Slagrev_now[ ζ_out[i] ] ] -= 1
    α1_Q = α0_Q .+ N0
    eSt = [1.0*(ii==S[tt]) for ii in 1:K]

    kuse = unique(Slagrev_now)
    nkuse = length(kuse)

    lmvbn0 = [ SparseProbVec.lmvbeta( α1_Q[:,kk] ) for kk in kuse ]
    lmvbn1 = [ SparseProbVec.lmvbeta( α1_Q[:,kk] + eSt ) for kk in kuse ]

    lw = zeros(Float64, R)

    for ℓ in 1:R
        lw[ℓ] = copy(lλ[ℓ])
        for kk in 1:nkuse
            if Slagrev_now[ℓ] == kuse[kk]
                lw[ℓ] += lmvbn1[kk]
            else
                lw[ℓ] += lmvbn0[kk]
            end
        end
    end

    w = exp.( lw - maximum(lw) )
    ζ_out[i] = StatsBase.sample(Weights( w ))
    N_now = copy(N0)
    N_now[ S[tt], Slagrev_now[ ζ_out[i] ] ] += 1

  end

  ζ_out
end
function rpost_ζ_mtd_marg(S::Vector{Int}, ζ_old::Vector{Int},
    prior_Q::Vector{SparseDirMixPrior},
    lλ::Vector{Float64},
    TT::Int, R::Int, K::Int)

  ζ_out = copy(ζ_old)
  N_now = counttrans_mtd(S, TT, ζ_old, R, K) # rows are tos, cols are froms

  for i in 1:(TT-R)  # i indexes ζ, tt indexes S
    tt = i + R
    Slagrev_now = S[range(tt-1, step=-1, length=R)]
    N0 = copy(N_now)
    N0[ S[tt], Slagrev_now[ ζ_out[i] ] ] -= 1
    # α1_Q = α0_Q + N0
    eSt = [1*(ii==S[tt]) for ii in 1:K]

    kuse = unique(Slagrev_now)
    nkuse = length(kuse)

    lSDMmarg0 = [ logSDMmarginal(N0[:,kk], prior_Q[kk].α, prior_Q[kk].β) for kk in kuse ]
    lSDMmarg1 = [ logSDMmarginal(N0[:,kk] + eSt, prior_Q[kk].α, prior_Q[kk].β) for kk in kuse ]

    lw = zeros(Float64, R)

    for ℓ in 1:R
        lw[ℓ] = copy(lλ[ℓ])
        for kk in 1:nkuse
            if Slagrev_now[ℓ] == kuse[kk]
                lw[ℓ] += lSDMmarg1[kk]
            else
                lw[ℓ] += lSDMmarg0[kk]
            end
        end
    end

    w = exp.( lw - maximum(lw) )
    ζ_out[i] = StatsBase.sample(Weights( w ))
    N_now = copy(N0)
    N_now[ S[tt], Slagrev_now[ ζ_out[i] ] ] += 1

  end

  ζ_out
end
function rpost_ζ_mtd_marg(S::Vector{Int}, ζ_old::Vector{Int},
    prior_Q::Union{Vector{SparseSBPrior}, Vector{SparseSBPriorP}},
    lλ::Vector{Float64},
    TT::Int, R::Int, K::Int)

  ζ_out = copy(ζ_old)
  N_now = counttrans_mtd(S, TT, ζ_old, R, K) # rows are tos, cols are froms

  for i in 1:(TT-R)  # i indexes ζ, tt indexes S
    tt = i + R
    Slagrev_now = S[range(tt-1, step=-1, length=R)]
    N0 = copy(N_now)
    N0[ S[tt], Slagrev_now[ ζ_out[i] ] ] -= 1
    eSt = [1*(ii==S[tt]) for ii in 1:K]

    kuse = unique(Slagrev_now)
    nkuse = length(kuse)

    if typeof(prior_Q) == Vector{SparseSBPrior}
        p1_now = [ prior_Q[kk].p1 for kk in kuse]
    elseif typeof(prior_Q) == Vector{SparseSBPriorP}
        p1_now = [ prior_Q[kk].p1_now for kk in kuse]
    end

    lSBMmarg0 = [ logSBMmarginal(N0[:,kuse[kk]], p1_now[kk], prior_Q[kuse[kk]].η, prior_Q[kuse[kk]].μ, prior_Q[kuse[kk]].M) for kk in 1:nkuse ]
    lSBMmarg1 = [ logSBMmarginal(N0[:,kuse[kk]] + eSt, p1_now[kk], prior_Q[kuse[kk]].η, prior_Q[kuse[kk]].μ, prior_Q[kuse[kk]].M) for kk in 1:nkuse ]

    lw = zeros(Float64, R)

    for ℓ in 1:R
        lw[ℓ] = copy(lλ[ℓ])
        for kk in 1:nkuse
            if Slagrev_now[ℓ] == kuse[kk]
                lw[ℓ] += lSBMmarg1[kk]
            else
                lw[ℓ] += lSBMmarg0[kk]
            end
        end
    end

    w = exp.( lw .- maximum(lw) )
    ζ_out[i] = StatsBase.sample(Weights( w ))
    N_now = copy(N0)
    N_now[ S[tt], Slagrev_now[ ζ_out[i] ] ] += 1

  end

  ζ_out
end



"""
    MetropIndep_λζ(S::Vector{Int}, lλ_old::Vector{Float64}, ζ_old::,
        prior_λ, prior_Q,
        TT::Int, R::Int, K::Int)

    Independence Metropolis step for λ and ζ.
    Currently assumes M=1.
"""
function MetropIndep_λζ(S::Vector{Int}, lλ_old::Vector{Float64}, ζ_old::Vector{Int},
    prior_λ::SparseDirMixPrior,
    prior_Q::Union{Vector{SparseSBPrior}, Vector{SparseSBPriorP}},
    TT::Int, R::Int, K::Int)

  lλ_cand = SparseProbVec.rSparseDirMix(prior_λ.α, prior_λ.β, true)
  λ_cand = exp.(lλ_cand)
  ζ_cand = [ StatsBase.sample( Weights(λ_cand) ) for i in 1:(TT-R) ]

  N_cand = counttrans_mtd(S, TT, ζ_cand, R, K) # rows are tos, cols are froms
  N_old = counttrans_mtd(S, TT, ζ_old, R, K) # rows are tos, cols are froms

  if typeof(prior_Q[1]) == SparseSBPrior
      p1_now = [ copy( prior_Q[kk].p1 ) for kk in 1:K ]
  elseif typeof(prior_Q[1]) == SparseSBPriorP
      p1_now = [ copy( prior_Q[kk].p1_now ) for kk in 1:K ]
  end

  lSBMmarg_cand = [ logSBMmarginal(N_cand[:,kk], p1_now[kk], prior_Q[kk].η, prior_Q[kk].μ, prior_Q[kk].M) for kk in 1:K ]
  lSBMmarg_old = [ logSBMmarginal(N_old[:,kk], p1_now[kk], prior_Q[kk].η, prior_Q[kk].μ, prior_Q[kk].M) for kk in 1:K ]

  ll_cand = sum( lSBMmarg_cand )
  ll_old = sum( lSBMmarg_old )

  lu = log(rand())
  if lu < (ll_cand - ll_old)
      lλ_out = lλ_cand
      ζ_out = ζ_cand
  else
      lλ_out = lλ_old
      ζ_out = ζ_old
  end

  (lλ_out, ζ_out)
end
function MetropIndep_λζ(S::Vector{Int}, lλ_old::Vector{Float64}, ζ_old::Vector{Int},
    prior_λ::Vector{Float64},
    prior_Q::Union{Vector{SparseSBPrior}, Vector{SparseSBPriorP}},
    TT::Int, R::Int, K::Int)

  lλ_cand = SparseProbVec.rDirichlet(prior_λ, true)
  λ_cand = exp.(lλ_cand)
  ζ_cand = [ StatsBase.sample( Weights(λ_cand) ) for i in 1:(TT-R) ]

  N_cand = counttrans_mtd(S, TT, ζ_cand, R, K) # rows are tos, cols are froms
  N_old = counttrans_mtd(S, TT, ζ_old, R, K) # rows are tos, cols are froms

  if typeof(prior_Q[1]) == SparseSBPrior
      p1_now = [ copy( prior_Q[kk].p1 ) for kk in 1:K ]
  elseif typeof(prior_Q[1]) == SparseSBPriorP
      p1_now = [ copy( prior_Q[kk].p1_now ) for kk in 1:K ]
  end

  lSBMmarg_cand = [ logSBMmarginal(N_cand[:,kk], p1_now[kk], prior_Q[kk].η, prior_Q[kk].μ, prior_Q[kk].M) for kk in 1:K ]
  lSBMmarg_old = [ logSBMmarginal(N_old[:,kk], p1_now[kk], prior_Q[kk].η, prior_Q[kk].μ, prior_Q[kk].M) for kk in 1:K ]

  ll_cand = sum( lSBMmarg_cand )
  ll_old = sum( lSBMmarg_old )

  lu = log(rand())
  if lu < (ll_cand - ll_old)
      lλ_out = lλ_cand
      ζ_out = ζ_cand
  else
      lλ_out = lλ_old
      ζ_out = ζ_old
  end

  (lλ_out, ζ_out)
end
function MetropIndep_λζ(S::Vector{Int}, lλ_old::Vector{Float64}, ζ_old::Vector{Int},
    prior_λ::SparseDirMixPrior,
    prior_Q::Matrix{Float64},
    TT::Int, R::Int, K::Int)

  lλ_cand = SparseProbVec.rSparseDirMix(prior_λ.α, prior_λ.β, true)
  λ_cand = exp.(lλ_cand)
  ζ_cand = [ StatsBase.sample( Weights(λ_cand) ) for i in 1:(TT-R) ]

  N_cand = counttrans_mtd(S, TT, ζ_cand, R, K) # rows are tos, cols are froms
  N_old = counttrans_mtd(S, TT, ζ_old, R, K) # rows are tos, cols are froms

  lDirmarg_cand = [ SparseProbVec.lmvbeta(N_cand[:,kk] .+ prior_Q[:,kk]) for kk in 1:K ] # can ignore denominator
  lDirmarg_old = [ SparseProbVec.lmvbeta(N_old[:,kk] .+ prior_Q[:,kk]) for kk in 1:K ]

  ll_cand = sum( lDirmarg_cand )
  ll_old = sum( lDirmarg_old )

  lu = log(rand())
  if lu < (ll_cand - ll_old)
      lλ_out = lλ_cand
      ζ_out = ζ_cand
  else
      lλ_out = lλ_old
      ζ_out = ζ_old
  end

  (lλ_out, ζ_out)
end
function MetropIndep_λζ(S::Vector{Int}, lλ_old::Vector{Float64}, ζ_old::Vector{Int},
    prior_λ::Vector{Float64},
    prior_Q::Matrix{Float64},
    TT::Int, R::Int, K::Int)

  lλ_cand = SparseProbVec.rDirichlet(prior_λ, true)
  λ_cand = exp.(lλ_cand)
  ζ_cand = [ StatsBase.sample( Weights(λ_cand) ) for i in 1:(TT-R) ]

  N_cand = counttrans_mtd(S, TT, ζ_cand, R, K) # rows are tos, cols are froms
  N_old = counttrans_mtd(S, TT, ζ_old, R, K) # rows are tos, cols are froms

  lDirmarg_cand = [ SparseProbVec.lmvbeta(N_cand[:,kk] .+ prior_Q[:,kk]) for kk in 1:K ] # can ignore denominator
  lDirmarg_old = [ SparseProbVec.lmvbeta(N_old[:,kk] .+ prior_Q[:,kk]) for kk in 1:K ]

  ll_cand = sum( lDirmarg_cand )
  ll_old = sum( lDirmarg_old )

  lu = log(rand())
  if lu < (ll_cand - ll_old)
      lλ_out = lλ_cand
      ζ_out = ζ_cand
  else
      lλ_out = lλ_old
      ζ_out = ζ_old
  end

  (lλ_out, ζ_out)
end


"""
mcmc_mtd!(model::ModMTD, n_keep::Int, save::Bool=true,
    report_filename::String="out_progress.txt", thin::Int=1, jmpstart_iter::Int=25,
    report_freq::Int=1000;
    monitorS_indx::Vector{Int}=[1])
"""
function mcmc_mtd!(model::ModMTD, n_keep::Int, save::Bool=true,
    report_filename::String="out_progress.txt", thin::Int=1, jmpstart_iter::Int=25,
    report_freq::Int=1000;
    monitorS_indx::Vector{Int}=[1])

    ## output files
    report_file = open(report_filename, "a+")
    write(report_file, "Commencing MCMC at $(Dates.now()) for $(n_keep * thin) iterations.\n")

    if save
        monitorS_len = length(monitorS_indx)
        sims = PostSimsMTD(  zeros(Float64, n_keep, model.R), # λ
        zeros(Float64, n_keep, model.K^2), # Q
        zeros(Int, n_keep, monitorS_len), # ζ
        zeros(Float64, n_keep), # p1λ
        zeros(Float64, n_keep, model.K) #= p1Q =# )
    end

    ## flags
    λSBMp_flag = typeof(model.prior.λ) == SparseProbVec.SparseSBPriorP
    λSBMfull_flag = typeof(model.prior.λ) == SparseProbVec.SparseSBPriorFull
    QSBMp_flag = typeof(model.prior.Q) == Vector{SparseProbVec.SparseSBPriorP}
    QSBMfull_flag = typeof(model.prior.Q) == Vector{SparseProbVec.SparseSBPriorFull}

    ## sampling
    for i in 1:n_keep
        for j in 1:thin

            jmpstart = (model.iter % jmpstart_iter == 0)

            if jmpstart

                model.state.lλ, model.state.ζ = MetropIndep_λζ(model.S,
                    model.state.lλ, model.state.ζ, model.prior.λ,
                    model.prior.Q,
                    model.TT, model.R, model.K)

            else

                model.state.ζ = rpost_ζ_mtd_marg(model.S, model.state.ζ,
                    model.prior.Q, model.state.lλ,
                    model.TT, model.R, model.K)

                if λSBMp_flag || λSBMfull_flag
                    model.state.lλ = rpost_lλ_mtd!(model.prior.λ, model.state.ζ, model.R)
                else
                    model.state.lλ = rpost_lλ_mtd(model.prior.λ, model.state.ζ, model.R)
                end

            end

            if QSBMp_flag || QSBMfull_flag
                model.state.lQ = rpost_lQ_mtd!(model.S, model.TT, model.prior.Q,
                    model.state.ζ, model.R, model.K)
            else
                model.state.lQ = rpost_lQ_mtd(model.S, model.TT, model.prior.Q,
                    model.state.ζ, model.R, model.K)
            end

            model.iter += 1
            if model.iter % report_freq == 0
                write(report_file, "Iter $(model.iter) at $(Dates.now())\n")
            end
        end

        if save
            @inbounds sims.λ[i,:] = exp.( model.state.lλ )
            @inbounds sims.Q[i,:] = exp.( vec( model.state.lQ ) )
            @inbounds sims.ζ[i,:] = copy(model.state.ζ[monitorS_indx])
            if λSBMp_flag || λSBMfull_flag
                sims.p1λ[i] = copy(model.prior.λ.p1_now)
            end
            if QSBMp_flag || QSBMfull_flag
                for kk in 1:model.K
                    sims.p1Q[i,kk] = copy( model.prior.Q[kk].p1_now )
                end
            end
        end
    end

    close(report_file)

    if save
        return sims
    else
        return model.iter
    end

end