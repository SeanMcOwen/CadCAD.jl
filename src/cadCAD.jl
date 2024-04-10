module cadCAD

include("spaces.jl")

# using .Spaces

# @space begin
#     myname::String
#     age::Int64
# end

# #println(fieldnames(State))

# A = @NamedTuple begin
#     a::Float64
#     b::String
# end
# println(fieldnames(A))

import TOML

using Base.Threads, Base.Libc, Logging, Comonicon, TerminalLoggers
using .Simulation, .MetaEngine

const old_logger = global_logger(TerminalLogger(right_justify=120))

"""
cadCAD.jl v0.1.0

# Arguments

- `toml_path`: path to the experiment TOML # Should be optional
"""
@main function main(toml_path)
    println(raw"""
                          _  ____    _    ____    _ _
             ___ __ _  __| |/ ___|  / \  |  _ \  (_) |
            / __/ _` |/ _` | |     / _ \ | | | | | | |
           | (_| (_| | (_| | |___ / ___ \| |_| | | | |
            \___\__,_|\__,_|\____/_/   \_\____(_)/ |_|
                                               |__/
          """)

    exit_on_escalation()

    # TODO: 
    if !@isdefined toml_path
        @error "A TOML path was not given."
        exit(1)
    end

    exp_config = TOML.tryparsefile(toml_path)

    @info """
    \nStarting experiment $(exp_config["title"]) based on $toml_path
    With system model composed of:
    $(exp_config["simulations"]["data_structures"]) as the data structures
    and
    $(exp_config["simulations"]["functions"]) as the functions
    """

    try
        # TODO: Implement the inclusion of Python data structures from system models here
        include(exp_config["simulations"]["data_structures"])
    catch err
        @error "Inclusion of the system model's data structures failed with the following error: " err
        exit(1)
    end

    random_simulation_name = first(setdiff(keys(exp_config["simulations"]), ("data_structures", "functions")))
    random_init_condition = eval(Symbol(exp_config["simulations"][random_simulation_name]["initial_conditions"]))
    generate_state_type(random_init_condition)

    println()
    @info "The following State type was generated:"
    dump(State)
    println()

    try
        # TODO: Implement the inclusion of Python functions from system models here
        include(exp_config["simulations"]["functions"])
    catch err
        @error "Inclusion of the system model's functions failed with the following error:" err
        exit(1)
    end

    eval(export_sys_model_symbols())

    n_threads = nthreads()
    @info "Running cadCAD.jl with $n_threads thread(s)."

    for simulation_name in keys(exp_config["simulations"])
        if simulation_name in ("data_structures", "functions")
            continue
        elseif exp_config["simulations"][simulation_name]["enabled"]
            @info "Running simulation $simulation_name..."
            run_simulation(exp_config, simulation_name)
        else
            @info "Skipping simulation $simulation_name because it was disabled."
        end
    end
end

function exit_on_escalation()
    cadcad_id = getpid()

    @debug "This cadCAD process has PID: " cadcad_id

    # TODO: Add more OSs
    @static if Sys.islinux()
        if stat("/proc/$cadcad_id").uid == 0x0
            @error "Running cadCAD as a privileged process is forbidden."
            exit(1)
        end
    else
        @warn "Do not run cadCAD as a privileged process. Currently, there is no checking of that on your system."
    end
end

function export_sys_model_symbols()
    forbidden_list = [:CASTED_COMMANDS, :MetaEngine, :Simulation,
        :command_main, :comonicon_install, :comonicon_install_path,
        :exit_on_escalation, :export_sys_model_symbols, :julia_main, :main, :old_logger]

    exclusion_list = []
    export_list = []
    resulting_list = [:(export State)]

    for name in Base.names(cadCAD, all=true)
        if !(name in forbidden_list)
            push!(export_list, :(export $(name)))
        end
    end

    for name in Base.names(cadCAD, all=false, imported=true)
        push!(exclusion_list, :(export $(name)))
    end

    for name in Base.names(Main.Base, all=false, imported=true)
        push!(exclusion_list, :(export $(name)))
    end

    for name in Base.names(Main.Core, all=false, imported=true)
        push!(exclusion_list, :(export $(name)))
    end

    for expression in export_list
        if !(expression in exclusion_list || expression == :(export include) || '#' in string(expression))
            push!(resulting_list, :($(expression)))
        end
    end

    return Expr(:block, resulting_list...)
end

end
