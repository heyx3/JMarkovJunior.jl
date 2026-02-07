@markovjunior 'I' begin
	# Place cave seeds.
    @do_n 3 begin
        @rule I => R
    end
	# Grow the cave seeds and leave some veins behind.
    @do_n 6000 begin
        @rule Rb => bR
		@rule RI => bR
		@rule IRb => GRb
    end

	# Clean up the veins.
    @do_all begin
		@sequential
        @rule R => b
		@rule GG => SS
		@rule G => b
    end

	# Turn the veins into real minerals.
	@block repeat begin
		# Mark a vein as either Gold or Nitra.
		@do_n 1 begin
			@rule S => Y
			@rule S => R
		end
		# Flesh out that vein.
		@do_all begin
			@rule YS => YY
			@rule RS => RR
			@rule RS => RR
			@rule RS => RR
		end
	end
end