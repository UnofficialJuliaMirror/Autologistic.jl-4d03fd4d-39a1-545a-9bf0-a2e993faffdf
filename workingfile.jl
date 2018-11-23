# Development scratch file

# NB: in this script I'm trying to use begin/end blocks to allow "cell mode"
# functionality.  Use ALT+Enter to run the code in the begin/end "cell".

# === Set up the package development environment (e.g. after restarting kernel)
begin #-Setup tasks
    pwd()  #should be \"C:\\\\GitWorking\\\\Autologistic"
    using Pkg
    Pkg.activate(pwd())   #At cmd line, could use ]activate .
    
    using Revise
    using Autologistic
    using LightGraphs, Plots, Profile, ProfileView, SparseArrays

    include("test\\runtests.jl")
end


# === Trying to speed things up ===
n1 = 35
M = ALRsimple(grid4(n1,n1)[1], rand(n1^2,3))
@time S = sample(M,100);
