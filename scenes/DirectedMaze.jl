@markovjunior begin
    # Place a seed at the center of the map,
    #  and special color along the top and bottom.
	@draw_box 'w' min=0.5 size=0
    @draw_box 'N' min=(0, 1) max=1
    @draw_box 'B' min=0 max=(1, 0)

    # Draw a maze that heavily biases towards the bottom of the map.
    # At first it "collapses" from the white pixel down to the brown line,
    #   then it builds sharply upward.
	@do_all begin
		@rule wbb => wgw
		@rule wbN => wgw
		@rule wNN => wgw
		@infer begin
			@path 22 w => b => N
		end
	end

    # Clean up the colors.
	# Set up a Path inference to wipe along a cool direction.
	@do_all begin
		@rule g => w
		@rule N => w
		@rule B => w
		@infer begin
			@path 0 gN => wg => B
		end
	end
end