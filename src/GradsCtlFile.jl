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
	    # TODO: dtype, index, stnmap, title,
	    "title" => "",
	    "undef" => nothing,
	    # TODO: unpack, fileheader, XYHEADER, XYTRAILER, THEADER, HEADERBYTES, TRAILERBYTES, XVAR, YVAR, ZVAR, STID, TVAR, TOFFVAR, CACHESIZE, 
            "options" => Dict(
	        "template" => false,
		"endian"   => "native"
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
	    # TODO: EDEF, VECTORPAIRS
	    "vars" => Dict(
	        "num" => 0,
		"elem" => []  # Dict( "varname" > "", ... )
	    )
	    # TODO: ATTRIBUTE METADATA
        )
        return self
    end
end
