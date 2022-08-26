module GradsCtl

using NetCDF
using FortranFiles

export GradsCtlFile

export gcopen
export gcslice


mutable struct GradsCtlFile
    fname::String
    info::Dict{String,Any}

    function GradsCtlFile( fname )
        self = new()
	self.fname = fname
	self.info = Dict(
	    "dset" => "",
            "options" => Dict(
	        "template" => false
	    ),
	    "chsub" => [],  # Dict( "start" => 0, "end" => 0, "str" => "" )
            "xdef" => Dict(
	        "varname"  => "", # for NetCDF
	        "num"      => 0,
		"type"     => "",
		"start"    => 0,
		"interval" => 0,
		"levels"   => []
	    ),
            "ydef" => Dict(
	        "varname"  => "", # for NetCDF
	        "num"      => 0,
		"type"     => "",
		"start"    => 0,
		"interval" => 0,
		"levels"   => []
	    ),
            "zdef" => Dict(
	        "varname"  => "", # for NetCDF
	        "num"      => 0,
		"type"     => "",
		"start"    => 0,
		"interval" => 0,
		"levels"   => []
	    ),
            "tdef" => Dict(
	        "varname"  => "", # for NetCDF
	        "num"      => 0,
		"type"     => "",
		"start"    => "",
		"interval" => ""
	    ),
	    "vars" => Dict(
	        "num" => 0,
		"elem" => []  # Dict( "varname" > "",  )
	    )
        )
        return self
    end
end

#mutable struct GradsCtlFileInfoOptions
#    template::Bool
#end
#=
mutable struct GradsCtlFileInfoTdef
    num::Integer
    
    function GradsCtlFileInfoTdef()
        self = new()
	self.num = 0
	return self
    end
end
=#

#=
mutable struct GradsCtlFileInfo
#    tdef::Integer
    values::Dict{ String, Vector{String} }
#    options::GradsCtlFileInfoOptions
    tdef::GradsCtlFileInfoTdef
#    chsub  <- array

    function GradsCtlFileInfo()
        self = new()
	self.tdef = GradsCtlFileInfoTdef()
	return self
    end
end
=#


function gcopen( ctl_fname )
    gc = GradsCtlFile( ctl_fname )
    #g.fname = fname

    #----- Analysis of control file -----#

    mul_key = ""  # for multiple line statement
    for line in eachline( gc.fname )
#        println( line )

	words = split( line, " ", keepempty=false )

        # comment
        if occursin( r"^\s*\*", line )
	    continue
	end

   	#----- multiple line statement -----#
        if mul_key == "vars"
            if occursin( r"^endvars"i, words[1] )
	        mul_key = ""
		continue
	    end

            varname = words[1]
            tmp = split( words[1], "=>", keepempty=false )
            push!( gc.info["vars"]["elem"], Dict(
	        "varname"      => tmp[1],
	        "gradsvarname" => tmp[2] ) )
	    continue
	end

        #----- single line statement -----#
	mul_key = ""

        # DSET
        if occursin( r"^dset"i, words[1] )
	    gc.info["dset"] = words[2]
	    continue
	end

	# OPTIONS
        if occursin( r"^options"i, words[1] )
            for word in words[2:end]
#                println( "  -> $word" )

                if occursin( r"^template"i, word )
                    gc.info["options"]["template"] = true
		    continue
		end
                println("Partly ignored ($word) in $line")
            end
	    continue
	end

	# TDEF
        if occursin( r"^tdef"i, words[1] )
            if tryparse( Int, words[2] ) == nothing
	        gc.info["tdef"]["varname"] = words[2]
                popfirst!( words )
	    end
            gc.info["tdef"]["num"]      = parse( Int, words[2] )
            gc.info["tdef"]["type"]     = lowercase( words[3] )
            gc.info["tdef"]["start"]    = lowercase( words[4] )
            gc.info["tdef"]["interval"] = lowercase( words[5] )
	    continue
	end

	# CHSUB
        if occursin( r"^chsub"i, words[1] )
           push!( gc.info["chsub"], Dict(
	       "start" => parse( Int, words[2]),
	       "end"   => parse( Int, words[3]),
	       "str"   => words[4] ) )
           continue
        end

	# VARS
        if occursin( r"^vars"i, words[1] )
            gc.info["vars"]["num"] = parse( Int, words[2] )
	    mul_key = "vars"
	    continue
	end

#	for word in eachsplit( line )  # julia >= 1.8.0
#        for word in words
#            println( "  -> $word" )
#	end
#	return

        println( "Ignored: $line" )
    end


    #----- Additional analysis when the data are in NetCDF format -----#
    
    # Generate data file name for tstep=1
    dir = replace( gc.fname, r"/[^/]+$" => "" )
    dat_fname = gc.info["dset"]
    dat_fname = replace( dat_fname, r"^\^" => "$dir/" )
    dat_fname = replace( dat_fname, "%ch" => gc.info["chsub"][1]["str"] )

    # Read metadata
    nc = NetCDF.open( dat_fname, mode=NC_NOWRITE )
    gc.info["xdef"]["num"] = size( nc["lon"], 1 )
    gc.info["ydef"]["num"] = size( nc["lat"], 1 )
    gc.info["zdef"]["num"] = size( nc["lev"], 1 )

    return gc
end


function gcslice( gc::GradsCtlFile, t::Integer )
#    print( t )

    # TODO: determine files and slice range
    fname = "/ext/crmnas/work13/kodama/www/cmip6/g/g09f_2000/data_ll/02560x01280.zorg.torg/2000/ms_u_p850/ms_u_p850_200001.nc"

    # read data
    v = ncread( fname, "ms_u_p850", start=[1,1,1,t], count=[-1,-1,-1,1] )


    # write data
    fid = FortranFile( "test.grd", "w", access="direct", recl=4*2560*1280, convert="little-endian" )
    write( fid, rec=1, v )
    close( fid )
end



end  # module


# export JULIA_REVISE_POLL=1

# (@v1.4) pkg> dev .
### (@v1.4) pkg> dev /home/kodama/data/program/julia/GradsCtl

# julia> using Revise

# julia> using GradsCtl
