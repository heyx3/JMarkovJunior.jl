"Based on [https://github.com/mxgmn/MarkovJunior](mxgmn/MarkovJunior)"
module JMarkovJunior

using Random, Setfield, Profile
using OrderedCollections, GLFW, CImGui
using CSyntax # Simplifies CImGui calls
using Bplus; @using_bplus

"
Retrieves the key from an ordered dictionary (or element from an ordered set),
    by its index.

The OrderedCollections package doesnt have an official way to do this yet;
    see https://github.com/JuliaCollections/OrderedCollections.jl/issues/93.
"
function ordered_collection_get_idx(oc::Union{OrderedDict, OrderedSet}, idx::Integer)
    # Make sure cached ops have all been applied.
    iterate(oc)

    inner = if oc isa OrderedDict
        oc
    elseif oc isa OrderedSet
        oc.dict
    else
        error("Unhandled: ", typeof(oc))
    end

    return inner.keys[idx]
end


Bplus.@make_toggleable_asserts markovjunior_
#DEBUG: Enable debug mode.
# markovjunior_asserts_enabled() = true

"
A compile-time flag that disables accelerated lookups,
  falling back to simpler behavior that's much less likely to have bugs
"
const SKIP_CACHE = false


"Converts various pieces of MarkovJunior algorithm definitions into their DSL representation"
function dsl_string end

# Basics:
include("cells.jl")
include("rules.jl")
include("inference.jl")
include("sequences.jl")
include("dsl.jl")

# High-level:
include("renderer.jl")
include("gui.jl")


"A good sequence for testing and display"
const DEFAULT_SEQUENCE =
    if false # Short-paths maze generator:
        @markovjunior 'b' begin
            # Pick a source cell
            @do_n 1 begin
                @rule "b" => "w"
            end
            # Draw maze paths out from the cell
            @do_all begin
                @rule "bbw" => "wEw"
            end
            # Clean up
            @do_all begin
                @rule "E" => "w"
            end
        end

    elseif false # Random walk maze generator:
        @markovjunior 'b' begin
            # Pick a source pixel
            @do_n 1 begin
                @rule "b" => "R"
            end
            # Do a backtracking random walk to carve out maze paths
            @do_all begin
                @sequential
                @rule "Rbb" => "GGR"
                @rule "GGR" => "Rww"
                @rule "R" => "w"
            end
        end
    elseif true # Custom weirdness
        @markovjunior 'b' begin
            # White pixel in center, Blue line along top, Brown line along bottom
            @draw_box 'w' min=0.5 size=0
            @draw_box(
                min=(0, 1),
                max=1,
                'B'
            )
            @draw_box(
                size=(1, 0),
                max=(1, 0),
                'N'
            )

            # Draw maze paths from the white pixel towards the brown line
            @do_all begin
                @rule "wbb" => "wGw"
                @sequential
                @infer begin
                    @path "w" => 'b' => "N"
                    3.5
                end
            end

            # Clean up helper colors
            @do_all begin
                @rule "G" => "w"
                @rule "N" => "b"
                @rule "B" => "w"
            end
        end
    else # Blank screen
        @markovjunior 'b' begin end
    end

function main(; sequence::ParsedMarkovAlgorithm = DEFAULT_SEQUENCE,
                resolution::v2i = v2i(get_something(
                    markov_fixed_resolution(sequence),
                    (100, 100)
                )...),
                seed = @markovjunior_debug(0x1a2a3b4b5c6c7d8d, rand(UInt32))
             )::Int
    @game_loop begin
        INIT(v2i(800, 800), "Markov Junior Playground",
             vsync=VsyncModes.on)

        SETUP = begin
            LOOP.max_fps = nothing
            gui = GuiRunner(dsl_string(sequence), seed)
        end
        LOOP = begin
            if GLFW.WindowShouldClose(LOOP.context.window)
                break
            end

            gui_main(gui, LOOP.delta_seconds)
        end
        TEARDOWN = begin
            close(gui)
        end
    end

    return 0
end

# Precompile code using a basic sequence.
# The sequence logic is super type-unstable, so this is very important to performance.
function run_game(; sequence::ParsedMarkovAlgorithm = DEFAULT_SEQUENCE,
                    resolution::NTuple{2, Int} = get_something(
                        markov_fixed_resolution(sequence),
                        (50, 50)
                    ))
    @bp_check markov_fixed_dimension(sequence) in (nothing, 2)

    grid = fill(sequence.initial_fill, resolution)
    rng = PRNG(0x23423411)

    seq_state = start_sequence(sequence.main_sequence, grid, AllInference(), rng)
    while exists(seq_state)
        seq_state = execute_sequence(sequence.main_sequence, grid, rng, seq_state)
    end

    return grid
end
@info "Running once for precompilation..."
run_game()

end