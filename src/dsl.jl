# Defines the syntax of the Markov Junior language used in this app.


"A Markov algorithm parsed from our DSL (`@markovjunior ...`)"
struct ParsedMarkovAlgorithm
    initial_fill::UInt8
    main_sequence::Sequence_Ordered

    # Dimension is either undefined, specified vaguely as number of axes,
    #    or specified precisely as a resolution.
    dimension::Union{Nothing, Int, Tuple{Vararg{Int}}}
end

"Gets the initial cell state from a parsed Markov algorithm"
markov_initial_fill(pma::ParsedMarkovAlgorithm) = pma.initial_fill

"Gets the actual algorithm from a parsed Markov algorithm"
markov_main_sequence(pma::ParsedMarkovAlgorithm)::AbstractSequence = pma.main_sequence


"Gets the number of dimensions of the given parsed Markov Algorithm, if a fixed number exists"
function markov_fixed_dimension(pma::ParsedMarkovAlgorithm)::Optional{Int}
    if isnothing(pma.dimension)
        return nothing
    elseif pma.dimension isa Int
        return pma.dimension
    else
        return length(pma.dimension)
    end
end

"
Gets the fixed resolution of the given pased Markov Algorithm, if a fixed resolution exists.
If you know the dimensionality of this instance, use the other overload for type stability.
"
function markov_fixed_resolution(pma::ParsedMarkovAlgorithm)::Optional{Tuple{Vararg{Int}}}
    if isnothing(pma.dimension) || (pma.dimension isa Int)
        return nothing
    else
        return pma.dimension
    end
end
"
Gets the fixed resolution of the given pased Markov Algorithm, if a fixed resolution exists.
If you don't know the dimensionality of this instance, use the other type-unstable overload.
"
function markov_fixed_resolution(pma::ParsedMarkovAlgorithm,
                                 ::Val{N}
                                )::Optional{NTuple{N, Int}} where {N}
    if isnothing(pma.dimension) || (pma.dimension isa Int)
        return nothing
    else
        @bp_check(length(pma.dimension) == N,
                  "Expected NTuple{$N, Int}, got $(typeof(pma.dimension))")
        return pma.dimension
    end
end

"""
Generates a markov algorithm using our DSL.

```
@markovjunior  #=initial fill, defaults 'b': =# 'b'   #= optional fixed resolution or ndims: =# (100, 100)   begin
    # White pixel in center, Blue line along top, Brown line along bottom:
    @draw_box(
        min=(0.5, 0.5),
        size=(0, 0),
        'b'
    )
    @draw_box(
        min=(0, 1),
        max=(1, 1),
        'B'
    )
    @draw_box(
        size=(1, 0),
        max=(1, 0),
        'N'
    )

    @do_all begin
        @rule "wbb" "wGw"
        @sequential
        @infer begin
            @path "w" => 'b' => "N" recompute
            0 # Temperature
        end
    end

    @do_all begin
        @rule "G" "w"
        @rule "N" "b"
        @rule "B" "w"
    end

    # @do_n begin
    #     50; @sequential
    # end
end
````
"""
macro markovjunior(args...)
    return parse_markovjunior(args)
end


####################################
##   Internal parsing logic

"Raises an error using the given LineNumberNode to point to user source"
function raise_error_at(src::LineNumberNode, msg...)
    error_expr = :( error($(msg...)) )
    eval(Expr(:block, src, error_expr))
end

"Parses the arguments of a `@markovjunior` macro"
function parse_markovjunior(_macro_args::Tuple)::ParsedMarkovAlgorithm
    macro_args = collect(macro_args)

    # Decide on the initial fill value.
    initial_fill_char::Char = 'b'
    for (i, a) in enumerate(macro_args)
        if a isa Char
            initial_fill_char = a
            deleteat!(macro_args, i)
            break
        end
    end
    initial_fill = CELL_CODE_BY_CHAR[initial_fill_char]

    # Decide on the fixed-dimension.
    dims = nothing
    resolution = nothing
    final_dimension = nothing
    for (i, a) in enumerate(macro_args)
        if a isa Int
            @bp_check a > 0 "A Markov algorithm must be at least 1D; got $a"
            dims = a
            final_dimension = a

            deleteat!(macro_args, i)
            break
        elseif a isa Expr && a.head == :tuple && all((b isa Int) for b in a.args)
            @bp_check length(a.args) > 0 "A Markov Algorithm must be at least 1D; resolution tuple was empty"
            resolution = eval(a)
            dims = length(resolution)
            final_dimension = dims

            deleteat!(macro_args, i)
            break
        end
    end

    # Grab the main sequence.
    main_sequence = Vector{AbstractSequence}()
    for (i, a) in enumerate(macro_args)
        if a isa Expr && a.head == :block
            parse_markovjunior_block(
                BlockParseInputs(initial_fill, dims, resolution),
                a.args, main_sequence
            )

            deleteat!(macro_args, i)
            break
        end
    end

    # Finish up.
    @bp_check !isempty(macro_args) "Unexpected arguments: $macro_args"
    return ParsedMarkovAlgorithm(initial_fill, Sequence_Ordered(main_sequence), final_dimension)
end


struct BlockParseInputs
    initial_fill::Char
    dims::Optional{Int}
    resolution::Optional{Tuple{Vararg{Int}}}
end

function parse_markovjunior_block(inputs::BlockParseInputs,
                                  block_lines,
                                  output::Vector{AbstractSequence})
    if isempty(block_lines)
        return
    end

    last_src_line::Optional{LineNumberNode} = nothing
    for block_line in block_lines
        if block_line isa LineNumberNode
            last_src_line = block_line
        elseif block_line isa Expr && block_line.head == :macrocall
            push!(output, parse_markovjunior_block_entry(
                inputs,
                Val(block_line.args[1]::Symbol),
                block_line.args[2]::LineNumberNode,
                block_line.args[3:end]
            ))
        else
            raise_error_at(last_src_line, "Unexpected sequence expression: '", block_line, "'")
        end
    end
end

function peel_markovjunior_block_assignment(inout_block_args, name::Symbol)::Optional{Some}
    for (i, a) in enumerate(inout_block_args)
        if a isa Expr && a.head == :(=) && a.args[1] == name
            value = a.args[2]
            deleteat!(inout_block_args, i)
            return value
        end
    end
    return nothing
end

function parse_markovjunior_block_entry(inputs::BlockParseInputs,
                                        ::Val{LineSymbol},
                                        location::LineNumberNode,
                                        block_args
                                       )::AbstractSequence where {LineSymbol}
    raise_error_at(location, "Unknown sequence '", LineSymbol, "'")
end
function parse_markovjunior_block_entry(inputs::BlockParseInputs,
                                        ::Val{Symbol("@draw_box")},
                                        location::LineNumberNode,
                                        _block_args)
    block_args = collect(block_args)

    value::Optional{UInt8} = nothing
    for (i, a) in enumerate(block_args)
        if a isa Char
            if a in CELL_CODE_BY_CHAR
                value = CELL_CODE_BY_CHAR[a]
            else
                raise_error_at(location, "Unsupported color: '", a, "'")
            end

            deleteat!(block_args, i)
            break
        end
    end
    if isnothing(value)
        raise_error_at(location, "No pixel value was provided within @draw_box")
    end

    # Grab the box area's args.
    set_min = peel_markovjunior_block_assignment(block_args, :min)
    set_max = peel_markovjunior_block_assignment(block_args, :max)
    set_size = peel_markovjunior_block_assignment(block_args, :size)
    n_set_box_params = (isnothing(set_min) ? 0 : 1) +
                       (isnothing(set_max) ? 0 : 1) +
                       (isnothing(set_size) ? 0 : 1)
    if n_set_box_params != 2
        raise_error_at(location,
                       "Must provide exactly TWO of min/max/size -- got ", n_set_box_params, "!")
    end

    # Compute their actual values/dimensions.
    function get_measure(expr, name)::Tuple{Union{Nothing, Int, Tuple{Vararg{Int}}},
                                            Optional{Int}}
        if isnothing(expr)
            return (nothing, nothing)
        end
        value = eval(expr)
        if value isa Int
            return (value, 1)
        elseif value isa Tuple{Vararg{Int}}
            return (value, length(value))
        else
            raise_error_at(location, "Unexpected value for '", name, "': ", typeof(value))
        end
    end
    (value_min, dims_min) = get_measure(set_min, :min)
    (value_max, dims_max) = get_measure(set_max, :max)
    (value_size, dims_size) = get_measure(set_size, :size)

    # Check the dimensions, and broadcast 1D values to all axes.
    #TODO: Implement

    #TODO: Finish
end
#TODO: Other sequences