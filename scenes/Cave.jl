@markovjunior 'I' begin
    @do_n 1 begin
        @rule I => b
    end
    @do_n 5000 begin
        @rule bI => gb
        @rule gI => bg
        @rule gb => bb
		@rule gb => gg
    end

	@do_n 100 begin
		@rule bgb => bbb
	end
	@do_all begin
		@rule Ig => II
		@rule Ig => gg
		@rule Ig => bb
	end

	@do_all begin
		@rule g => S
	end
end