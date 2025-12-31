@bp_bitflag(MarkovJuniorGuiRenderFlags,
    NONE,
    potentials, rules
)
const GUI_LEGEND_DATA = map(enumerate(CELL_TYPES)) do i,t
    return (
        t.color,
        Float32(i)/Float32(length(CELL_TYPES)),
        " - $(t.char)"
    )
end

"The state of the GUI for our MarkovJunior tool"
mutable struct GuiRunner
    draw_monochrome::Bool
    draw_flags::E_MarkovJuniorGuiRenderFlags

    next_dimensionality::Int
    next_resolution::Vector{Int}

    state_grid::CellGrid
    state_grid_tex2D_slice::CellGrid{2}
    state_texture::Texture

    algorithm::ParsedMarkovAlgorithm
    algorithm_state::Optional
    algorithm_rng::PRNG

    algorithm_render2D::Ref{Texture}
    algorithm_render2D_buffer::Ref{Matrix{v3f}}

    current_seed::UInt64
    current_seed_display::String
    next_seed::GuiText

    next_algorithm::GuiText
    algorithm_error_msg::String

    is_playing::Bool
    ticks_per_second::Float32
    time_till_next_tick::Float32

    ticks_per_jump::Int
    ticks_for_profile::Int
    max_seconds_for_run_to_end::Float32
end

function GuiRunner(initial_algorithm_str::String,
                   seed="0x1234567890abcdef")
    # Create a half-baked initial instance, then "restart" the algorithm.
    fake_size = 64
    runner = GuiRunner(
        false, MarkovJuniorGuiRenderFlags.NONE,

        2, [ fake_size, fake_size ],
        fill(zero(UInt8), fake_size, fake_size),
        fill(zero(UInt8), fake_size, fake_size),
        Texture(SpecialFormats.rgb10_a2, v2u(1, 2)), # Size must not match fake_size
                                                     #   or else it won't be properly reallocated

        @markovjunior begin end, nothing, PRNG(1),
        Ref{Texture}(), Ref{Matrix{v3f}}(),
        zero(UInt64), "[NULL]",
        GuiText(string(seed)),

        GuiText(initial_algorithm_str,
            is_multiline=true,
            imgui_flags=CImGui.LibCImGui.ImGuiInputTextFlags_AllowTabInput
        ),
        "Uh-OH: UNINITIALIZED!!!!",

        false, 5.0f0, -1.0f0,

        10, 1000, 10.0f0
    )

    reset_gui_runner_algo(runner, true, true)
    update_gui_runner_texture_2D(runner)

    return runner
end
function Base.close(runner::GuiRunner)
    close(runner.state_texture)
    close(runner.algorithm_render2D)
end

function update_gui_runner_texture_2D(runner::GuiRunner)
    if (state_texture.type != TextureTypes.twoD) || (state_texture.size.xy != vsize(runner.state_grid).xy)
        runner.state_texture = Texture(
            SimpleFormat(
                FormatTypes.uint,
                SimpleFormatComponents.R,
                SimpleFormatBitDepths.B4
            ),
            runner.state_grid,
            sampler = TexSampler{1}(
                pixel_filter = PixelFilters.rough
            ),
            n_mips = 0
        )
        runner.state_grid_tex2D_slice = fill(zero(UInt8), runner.state_texture.size.xy...)
    else
        runner.state_grid_tex2D_slice .= @view runner.state_grid[
            ntuple(i -> (i>2) ? 1 : Colon(),
                   ndims(runner.state_grid))...
        ]
        set_tex_pixels(runner.state_texture, runner.state_grid_tex2D_slice)
    end

    render_markov_2d(runner.state_grid_tex2D_slice, v3f(0.2, 0.2, 0.2),
                     runner.algorithm_render2D_buffer,
                     runner.algorithm_render2D)

    return nothing
end

function reset_gui_runner_algo(runner::GuiRunner,
                               parse_new_seed::Bool, parse_new_algorithm::Bool)
    # Re-parse the algorithm textbox, if requested.
    if parse_new_algorithm
        runner.algorithm_error_msg = ""
        try
            algorithm_ast = Meta.parse(string(runner.next_algorithm))
            if !Base.isexpr(algorithm_ast, :macrocall) || algorithm_ast.args[1] != Symbol("@markovjunior")
                runner.algorithm_error_msg = string(
                    "Invalid header: Expected `@markovjunior ... begin ... end`",
                    "\n\nFalling back to previous successfully-parsed algorithm"
                )
            else
                runner.algorithm = eval(algorithm_ast)
            end
        catch e
            runner.algorithm_error_msg = string(
                "Failed to parse: ", sprint(io -> showerror(io, e)),
                "\n\nFalling back to previous successfully-parsed algorithm"
            )
        end

        # If the algorithm has a fixed dimensionality, trim 'next_resolution' to fit.
        n_dims = markov_fixed_dimension(runner.algorithm)
        if exists(n_dims)
            while length(runner.next_resolution) < n_dims
                push!(runner.next_resolution, 1)
            end
            while length(runner.next_resolution) > n_dims
                deleteat!(runner.next_resolution, length(runner.next_resolution))
            end
        end
    end

    # Initialize the grid.
    dimensions = let d = markov_fixed_dimension(runner.algorithm)
        if exists(d)
            d
        else
            runner.next_dimensionality
        end
    end
    resolution = let r = markov_fixed_resolution(runner.algorithm)
        if exists(r)
            r
        else
            (runner.next_resolution...)
        end
    end
    runner.state_grid = fill(algorithm.initial_fill, resolution)

    # Initialize the RNG.
    if parse_new_seed
        as_int = tryparse(UInt64, string(runner.next_seed))
        runner.current_seed = if exists(as_int)
            as_int
        else
            hash(string(runner.next_seed))
        end

        runner.current_seed_display = "Seed: 0x$(string(runner.current_seed, base=16))"
    end
    runner.algorithm_rng = PRNG(PrngStrength.strong, runner.current_seed)

    # Initialize the algorithm sequence.
    runner.algorithm_state = execute_sequence(
        runner.algorithm.main_sequence,
        runner.state_grid, runner.algorithm_rng,
        start_sequence(runner.algorithm.main_sequence,
                       runner.state_grid, AllInference(),
                       runner.algorithm_rng)
    )

    # Reset other variables.
    runner.is_playing = false

    return nothing
end
function step_gui_runner_algo(runner::GuiRunner)
    if exists(runner.algorithm_state)
        runner.algorithm_state = execute_sequence(
            runner.algorithm.main_sequence,
            runner.state_grid, runner.algorithm_rng,
            runner.algorithm_state
        )
    end

    # Always stop Playing if the algorithm is finished.
    if isnothing(runner.algorithm_state)
        runner.is_playing = false
    end

    return nothing
end

gui_runner_is_finished(runner::GuiRunner)::Bool = isnothing(runner.algorithm_state)

function gui_main(runner::GuiRunner, delta_seconds::Float32)
    gui_next_window_space(Box2Df(
        min=v2f(0, 0),
        max=v2f(0.3, 1)
    ))
    gui_within_child_window("Runner", CImGui.LibCImGui.ImGuiWindowFlags_NoDecoration) do
        content_size = convert(v2f, CImGui.GetContentRegionAvail())

        # Render settings:
        @c CImGui.Selectable("Monochrome", &runner.draw_monochrome)
        CImGui.SameLine(0, 20)
        for (name, flag) in [ ("Potentials", MarkovJuniorGuiRenderFlags.potentials),
                                ("Rules", MarkovJuniorGuiRenderFlags.rules) ]
        #begin
            if runner.draw_monochrome
                if CImGui.Selectable(name, contains(flag, runner.draw_flags))
                    runner.draw_flags |= flag
                else
                    runner.draw_flags -= flag
                end
            else
                # Draw a disabled version of the widget.
                CImGui.Text(name)
            end
            CImGui.SameLine(0, 5)
        end
        CImGui.Dummy(0, 0) # To cancel the last SameLine() call

        # Current state:
        CImGui.BeginChild(CImGui.GetID("StateDisplayArea"),
                          ImVec2(content_size.x - 20,
                                 content_size.y - 200))
            CImGui.Image(gui_tex_handle(runner.algorithm_render2D[]),
                         convert(gVec2, runner.algorithm_render2D[].size.xy),
                         ImVec2(0, 0), ImVec2(1, 1),
                         ImVec4(1, 1, 1, 1), ImVec4(0, 0, 0, 0))
        CImGui.EndChild()
        #TODO: Add B+ helper for scroll regions once this is verified working

        # Below actions may invalidate the algorithm state.
        should_update_texture = Ref(false)

        # Run buttons:
        #   * Step
        if CImGui.Button("Step")
            step_gui_runner_algo(runner)
            should_update_texture[] = true
        end
        CImGui.SameLine(0, 20)
        #   * Jump
        runner.ticks_per_jump = CImGui.DragInt("##TicksPerJump", runner.ticks_per_jump, 1.0, 1, 0, "%d")
        CImGui.SameLine()
        if CImGui.Button("Jump")
            for i in 1:runner.ticks_per_jump
                step_gui_runner_algo(runner)
                should_update_texture[] = true
            end
        end
        CImGui.SameLine(0, 20)
        #    * Play/Pause
        if runner.is_playing
            runner.time_till_next_tick -= delta_seconds
            while runner.time_till_next_tick <= 0
                step_gui_runner_algo(runner)
                should_update_texture[] = true
                runner.time_till_next_tick += 1.0f0 / runner.ticks_per_second
            end
        end
        runner.ticks_per_second = CImGui.DragFloat("##TicksPerSecond", runner.ticks_per_second, 1.0, 0.00001, 0, "%f", 1.0)
        CImGui.SameLine()
        new_is_playing::Bool = CImGui.Selectable(runner.is_playing ? "Pause" : "Play",
                                                 runner.is_playing)
        if new_is_playing && !runner.is_playing
            runner.time_till_next_tick = 1.0f0 / runner.ticks_per_second
        end
        runner.is_playing = new_is_playing

        # Special control buttons:
        gui_with_style(CImGui.LibCImGui.ImGuiCol_Button, v3f(1, 0.6, 0.7)) do
            runner.max_seconds_for_run_to_end = CImGui.DragFloat(
                "##MaxSecondsRunningToEnd",
                runner.max_seconds_for_run_to_end,
                1.0, 0.0, 0.0, "%f", 1.0
            )
            CImGui.SameLine()
            CImGui.Tooltip("Max seconds, before canceling the run-to-end")
            if CImGui.Button("Run to End")
                start_t = time()
                while !gui_runner_is_finished(runner)
                    step_gui_runner_algo(runner)
                    should_update_texture[] = true

                    if (time() - start_t) > runner.max_seconds_for_run_to_end
                        runner.algorithm_error_msg = string(
                            "ENDLESS RUN DETECTED: took longer than ",
                            runner.max_seconds_for_run_to_end, " seconds to run to the end!",
                            "\n\nYou may increase this cutoff time if you like."
                        )
                        break
                    end
                end
            end
            CImGui.SameLine(0, 40)
            if CImGui.Button("Reset")
                reset_gui_runner_algo(runner, false, false)
                should_update_texture[] = true
            end
            CImGui.SameLine(0, 20)
            runner.ticks_for_profile = CImGui.DragInt("##TicksForProfile", runner.ticks_for_profile, 1.0, 1, 0, "%d")
            CImGui.SameLine()
            if CImGui.Button("Profile")
                Profile.start_timer()
                for i in 1:runner.ticks_for_profile
                    step_gui_runner_algo(runner)
                    if gui_runner_is_finished(runner)
                        break
                    end
                end
                Profile.stop_timer()

                #TODO: Pop up a modal view of the profile data
            end
            CImGui.SameLine(0, 10)
            CImGui.Text("#TODO: profiled modal view")
        end

        # Seed data:
        CImGui.Text(runner.current_seed_display)
        CImGui.SameLine(0, 40)
        gui_text!(runner.next_seed)
        CImGui.SameLine(0, 10)
        if CImGui.Button("Restart##WithNewSeed")
            reset_gui_runner_algo(runner, true, false)
            should_update_texture[] = true
        end
        CImGui.SameLine(0, 20)
        CImGui.Text(isnothing(tryparse(UInt64, runner.next_seed)) ?
                      "as String" :
                      "as number")

        # Update the state texture, if any above code changed the state.
        if should_update_texture[]
            update_gui_runner_texture_2D(runner)
        end
    end

    gui_next_window_space(Box2Df(
        min=v2f(0.3, 0),
        max=v2f(0.4, 0.5)
    ))
    gui_within_child_window("Legend", CImGui.LibCImGui.ImGuiWindowFlags_NoDecoration) do
        gui_within_group() do
            for (color, greyscale, text) in GUI_LEGEND_DATA
                gui_draw_rect(
                    GuiDrawCursorRelative(Box2Df(
                        min=v2f(0, 0),
                        size=v2f(40, 40)
                    ), v2f(1, 0)),
                    GuiDrawFilled(color)
                )
                CImGui.Text(text)
            end
        end

        #TODO: Also display a rules legend
    end

    gui_next_window_space(Box2Df(
        min=v2f(0.4, 0),
        max=v2f(0.7, 1)
    ))
    gui_within_child_window("Editor", CImGui.LibCImGui.ImGuiWindowFlags_NoDecoration) do
        content_size = convert(v2f, CImGui.GetContentRegionAvail())

        runner.next_algorithm.multiline_requested_size = round.(Ref(Int),
            (content_size - v2f(20, 50)).data
        )
        gui_text!(runner.next_algorithm)

        if CImGui.Button("Restart##WithNewAlgorithm")
            reset_gui_runner_algo(runner, false, true)
        end
    end

    #TODO: File management window
end