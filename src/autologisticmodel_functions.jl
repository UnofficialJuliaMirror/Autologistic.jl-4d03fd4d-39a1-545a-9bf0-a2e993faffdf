# A fcn to convert Boolean responses into coded values.
# Returns a 2D array of Float64.  If Y is not supplied, use the responses stored
# in the 1st argument.
function makecoded(M::AutologisticModel, Y=nothing)
    if Y==nothing
        Y = M.responses
    else
        Y = makebool(Y)
    end
    lo = M.coding[1]
    hi = M.coding[2]
    n, m = size(Y)
    out = Array{Float64,2}(undef, n, m)
    for j = 1:m
        for i = 1:n
            out[i,j] = Y[i,j] ? hi : lo
        end
    end
    return out
end


# === centering adjustment =====================================================
# centeringterms(M) returns an Array{Float64,2} of the same dimension as 
# M.unary, giving the centering adjustments for AutologisticModel M.
# centeringterms(M,kind) returns the centering adjustment that would be 
#   if centering were of type kind.
# TODO: consider performance implications of calculating this each time instead
# of storing the value.
function centeringterms(M::AutologisticModel, kind::Union{Nothing,CenteringKinds}=nothing) 
    k = kind==nothing ? M.centering : kind
    if k == none
        return fill(0.0, size(M.unary))
    elseif k == onehalf
        return fill(0.5, size(M.unary))
    elseif k == expectation
        lo, hi = M.coding
        α = M.unary[:,:] 
        num = lo*exp.(lo*α) + hi*exp.(hi*α)
        denom = exp.(lo*α) + exp.(hi*α)
        return num./denom
    else 
        error("centering kind not recognized")
    end
end


# === pseudolikelihood =========================================================
# pseudolikelihood(M) computes the negative log pseudolikelihood for the given 
# AutologisticModel with its responses.  Returns a Float64.
function pseudolikelihood(M::AutologisticModel)
    out = 0.0
    Y = makecoded(M)
    mu = centeringterms(M)
    lo, hi = M.coding

    # Loop through replicates
    for j = 1:size(Y)[2]
        y = Y[:,j];                     #-Current replicate's observations.
        α = M.unary[:,j]                #-Current replicate's unary parameters.
        μ = mu[:,j]                     #-Current replicate's centering terms.
        Λ = M.pairwise[:,:,j]           #-Current replicate's assoc. matrix.
        s = α + Λ*(y - μ)               #-(λ-weighted) neighbour sums + unary.
        logPL = sum(y.*s - log.(exp.(lo*s) + exp.(hi*s)))
        out = out - logPL               #-Subtract this rep's log PL from total.
    end

    return out

end


# === negpotential function ====================================================
# negpotential(M) returns an m-vector of Float64 negpotential values, where 
# m is the number of replicate observations found in M.responses.
# TODO: clean up for allocations/speed. Based on experience with sample(), might
#       want to loop explicitly.
function negpotential(M::AutologisticModel)
    Y = makecoded(M)
    m = size(Y,2)
    out = Array{Float64}(undef, m)
    α = M.unary[:,:]
    μ = centeringterms(M)
    for j = 1:m
        Λ = M.pairwise[:,:,j]
        out[j] = Y[:,j]'*α[:,j] - Y[:,j]'*Λ*μ[:,j]  + Y[:,j]'*Λ*Y[:,j]/2
    end
    return out
end


# === fullPMF ==================================================================
"""
    fullPMF(M::AutologisticModel; replicates=nothing, force::Bool=false)

Compute the PMF of an AutologisticModel, and return a `NamedTuple` `(:table, :partition)`.

For an AutologisticModel with ``n`` observations and ``m`` replicates, `:table` is a ``2^n×(n+1)×m`` 
array of `Float64`. Each page of the 3D array holds a probability table for a replicate.  
Each row of the table holds a specific configuration of the responses, with the 
corresponding probability in the last column.  In the ``m=1`` case,  `:table` is a 2D array.

Output `:partition` is a vector of normalizing constant (a.k.a. partition function) values.
In the ``m=1`` case, it is a scalar `Float64`.

# Arguments
- `M::AutologisticModel`: an autologistic model.
- `replicates=nothing`: indices of specific replicates from which to obtain the output. By 
  default, all replicates are used.
- `force::Bool=false`: calling the function with ``n>20`` will throw an error unless 
  `force=true`. 

# Examples
```jldoctest
julia> M = makeALRsimple(Graph(3,0),ones(3,1));
julia> pmf = fullPMF(M);
julia> pmf.table
8×4 Array{Float64,2}:
 -1.0  -1.0  -1.0  0.125
 -1.0  -1.0   1.0  0.125
 -1.0   1.0  -1.0  0.125
 -1.0   1.0   1.0  0.125
  1.0  -1.0  -1.0  0.125
  1.0  -1.0   1.0  0.125
  1.0   1.0  -1.0  0.125
  1.0   1.0   1.0  0.125
julia> pmf.partition
 8.0
```
"""
function fullPMF(M::AutologisticModel; replicates=nothing, force::Bool=false)
    n, m = size(M.unary)
    nc = 2^n
    if n>20 && !force
        error("Attempting to tabulate a PMF with more than 2^20 configurations."
              * "\nIf you really want to do this, set force=true.")
    end
    if replicates == nothing
        replicates = 1:m
    elseif minimum(replicates)<1 || maximum(replicates)>m 
        error("replicate index out of bounds")
    end
    lo = M.coding[1]
    hi = M.coding[2]
    T = zeros(nc, n+1, length(replicates))
    configs = zeros(nc,n)
    partition = zeros(m)
    for i in 1:n
        inner = [repeat([lo],Int(nc/2^i)); repeat([hi],Int(nc/2^i))]
        configs[:,i] = repeat(inner , 2^(i-1) )
    end
    for i in 1:length(replicates)
        r = replicates[i]
        T[:,1:n,i] = configs
        α = M.unary[:,r]
        Λ = M.pairwise[:,:,r]
        μ = centeringterms(M)[:,r]
        unnormalized = mapslices(v -> exp.(v'*α - v'*Λ*μ + v'*Λ*v/2), configs, dims=2)
        partition[i] = sum(unnormalized)
        T[:,n+1,i] = unnormalized / partition[i]
    end
    if length(replicates)==1
        T  = dropdims(T,dims=3)
        partition = partition[1]
    end
    return (table=T, partition=partition)
end

# ***TODO: documentation***
#Returns an n-by-m array (or an n-vector if  m==1). The [i,j]th element is the 
#marginal probability of the high state in the ith variable at the jth replciate.
function marginalprobabilities(M::AutologisticModel; replicates=nothing, force::Bool=false)
    n, m = size(M.unary)
    nc = 2^n
    if n>20 && !force
        error("Attempting to tabulate a PMF with more than 2^20 configurations."
              * "\nIf you really want to do this, set force=true.")
    end
    if replicates == nothing
        replicates = 1:m
    elseif minimum(replicates)<1 || maximum(replicates)>m 
        error("replicate index out of bounds")
    end
    hi = M.coding[2]
    out = zeros(n,length(replicates))

    tbl = fullPMF(M).table

    for j = 1:length(replicates)
        r = replicates[j]
        for i = 1:n
            out[i,j] = sum(mapslices(x -> x[i]==hi ? x[n+1] : 0.0, tbl[:,:,r], dims=2))
        end
    end
    if length(replicates) == 1
        return vec(out)
    end
    return out
end

# Compute the conditional probability that variables take the high state, given the
# current values of all of their neighbors. If vertices or replicates are provided,
# the results are only computed for the desired variables & replicates.  Otherwise
# results are computed for all variables and replicates.
# TODO: optimize for speed/efficiency
function conditionalprobabilities(M::AutologisticModel; vertices=nothing, replicates=nothing)
    n, m = size(M.unary)
    if vertices==nothing
        vertices = 1:n
    end
    if replicates==nothing
        replicates = 1:m
    end
    out = zeros(Float64, length(vertices), length(replicates))
    Y = makecoded(M)
    μ = centeringterms(M)
    lo, hi = M.coding
    adjlist = M.pairwise.G.fadjlist

    for j = 1:length(replicates)
        r = replicates[j]
        for i = 1:length(vertices)
            v = vertices[i]
            # get neighbor sum
            ns = 0.0
            for ix in adjlist[v]
                ns = ns + M.pairwise[v,ix,r] * (Y[ix,r] - μ[ix,r])
            end
            # get cond prob
            loval = exp(lo*(M.unary[v,r] + ns))
            hival = exp(hi*(M.unary[v,r] + ns))
            if hival == Inf
                out[i,r] = 1.0
            else
                out[i,r] = hival / (loval + hival)
            end
        end
    end
    return out
end
