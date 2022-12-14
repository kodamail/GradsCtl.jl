mutable struct GradsCtlFile
    fname::String
    ftype::String
    info::Dict{String,Any}

    function GradsCtlFile( fname )
        self = new()
	self.fname = fname
	self.ftype = ""
	self.info = Dict(
	    "dset" => "",
	    "chsub" => [],  # Dict( "start" => 0, "end" => 0, "str" => "" )
	    "dtype" => "",
	    "index" => "",
	    "stnmap" => "",
	    "title" => "",
	    "undef" => nothing,
	    # TODO: unpack, fileheader, XYHEADER, XYTRAILER, THEADER, HEADERBYTES, TRAILERBYTES, XVAR, YVAR, ZVAR, STID, TVAR, TOFFVAR, CACHESIZE, 
            "options" => Dict(
		"endian"           => "native",
	        "template"         => false,
	        "yrev"             => false,
	        "zrev"             => false,
	        "365_day_calendar" => false
	    ),
	    #TODO: pdef
            "xdef" => Dict(
	        "varname"  => "",
	        "num"      => 0,
		"type"     => "",
		"start"    => 0,
		"interval" => 0,
		"levels"   => []
	    ),
            "ydef" => Dict(
	        "varname"  => "",
	        "num"      => 0,
		"type"     => "",
		"start"    => 0,
		"interval" => 0,
		"levels"   => []
	    ),
            "zdef" => Dict(
	        "varname"  => "",
	        "num"      => 0,
		"type"     => "",
		"start"    => 0,
		"interval" => 0,
		"levels"   => []
	    ),
            "tdef" => Dict(
	        "varname"  => "",
	        "num"      => 0,
		"type"     => "",
		"start"    => "",
		"interval" => 0,
		"interval_unit" => ""
	    ),
            "edef" => Dict(
	        "num"     => 0,
		"ensname" => [],
		"length"  => [],
		"start"   => []
	    ),
	    # TODO: VECTORPAIRS
	    "vars" => Dict(
	        "num" => 0,
		"elem" => []  # Dict( "varname" > "", ... )
	    )
	    # TODO: ATTRIBUTE METADATA
        )
        return self
    end
end
