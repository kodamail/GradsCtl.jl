module GradsCtl

using NetCDF
using FortranFiles
using Dates

include("GradsCtlFile.jl")

export GradsCtlFile

export gcopen
#export gcslice
export gcslicewrite


"""
    gcopen( ctl_fname )

Open and analyze a GrADS control file
"""
function gcopen( ctl_fname )
    gc = GradsCtlFile( ctl_fname )

    #----- Analysis of control file -----#

    mul_status = ""  # status for multiple line statement
    for line in eachline( gc.fname )
#        println( line )
	words = split( line, " ", keepempty=false )

        # comment
        if occursin( r"^\s*\*", line )
	    continue
	end

   	#----- multiple-line statement -----#
        if mul_status == "vars"
            if occursin( r"^endvars"i, words[1] )
	        mul_status = ""
		continue
	    end

            varname = words[1]
            tmp = split( words[1], "=>", keepempty=false )
            push!( gc.info["vars"]["elem"], Dict(
	        "varname"      => tmp[1],
	        "gradsvarname" => tmp[2] ) )
	    continue
	end

        #----- single-line statement -----#
	mul_status = ""

        # DSET
        if occursin( r"^dset"i, words[1] )
	    gc.info["dset"] = words[2]
	    continue
	end

        # UNDEF
        if occursin( r"^undef"i, words[1] )
	    gc.info["undef"] = parse( Float32, replace( words[2], r"f$" => "" ) )
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
                error( "\"$word\" is not supported in $words[1]")
            end
	    continue
	end

	# TDEF
        if occursin( r"^tdef"i, words[1] )
            if tryparse( Int, words[2] ) == nothing
	        gc.info["tdef"]["varname"] = words[2]
                popfirst!( words )
	    end
            gc.info["tdef"]["num"]           = parse( Int, words[2] )
            gc.info["tdef"]["type"]          = lowercase( words[3] )
            gc.info["tdef"]["start"]         = lowercase( words[4] )
            gc.info["tdef"]["interval"]      = parse(Int,words[5][1:end-2])
            gc.info["tdef"]["interval_unit"] = lowercase(words[5][end-1:end])
	    continue
	end

	# CHSUB
        if occursin( r"^chsub"i, words[1] )
           push!( gc.info["chsub"], Dict(
	       "start" => parse( Int, words[2]),
	       "end"   => parse( Int, words[3]),
	       "str"   => words[4] ) )
	   # check continuity of timestep
	   if length( gc.info["chsub"] ) == 1
	       if gc.info["chsub"][end]["start"] != 1
	           error( "Time step of chsub must start from 1 (!=", gc.info["chsub"][end]["start"], ")" )
	       end
	   else
	       if gc.info["chsub"][end]["start"] != gc.info["chsub"][end-1]["end"] + 1
	           error( "chsub is not continuous: From ", gc.info["chsub"][end-1] , " To ", gc.info["chsub"][end] )
               end
	   end
           continue
        end

	# VARS
        if occursin( r"^vars"i, words[1] )
            gc.info["vars"]["num"] = parse( Int, words[2] )
	    mul_status = "vars"
	    continue
	end

        error( "Fail to analyze \"$line\"" )
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


#TODO: function gcslice: same as gslicewrite but returning array instead of file output

"""
    gcslicewrite( gc, varname, out_fname, ...

Write sliced data to a file
"""
function gcslicewrite( gc::GradsCtlFile,
    	 	       varname::String,
    	 	       out_fname::String;
		       ymd_range::String="",
		       cal_range::String="",
		       t_int::Integer=1,
		       out_endian::String="native")  # "little-endian" or "big-endian"

    #-----Analyze argument -----#

    # varname
    for elem in gc.info["vars"]["elem"]
        if varname == elem["gradsvarname"]
	    varname = elem["varname"]
	end
    end

    # ymd_range, cal_range
    if ymd_range != ""
        m = match( r"(?<incflag_start>.)(?<date_start>\d+):(?<date_end>\d+)(?<incflag_end>.)", ymd_range )
        if m === nothing
            error( "Invalid ymd_range: $ymd_range" )
        end
        datetime_start = DateTime( m[:date_start], dateformat"yyyymmdd" )
        datetime_end   = DateTime( m[:date_end], dateformat"yyyymmdd" )
        incflag_start = m[:incflag_start] == "(" ? false : true
        incflag_end   = m[:incflag_end]   == ")" ? false : true
    
    elseif cal_range != ""
        m = match( r"(?<incflag_start>.)(?<date_start>\d+)\.(?<hms_start>\d+):(?<date_end>\d+)\.(?<hms_end>\d+)(?<incflag_end>.)", cal_range )
        if m === nothing
            error( "Invalid cal_range: $cal_range" )
        end
        datetime_start = DateTime( m[:date_start]*m[:hms_start], dateformat"yyyymmddHHMMSS" )
        datetime_end   = DateTime( m[:date_end]*m[:hms_end], dateformat"yyyymmddHHMMSS" )
        incflag_start = m[:incflag_start] == "(" ? false : true
        incflag_end   = m[:incflag_end]   == ")" ? false : true
        
    else
	error("Time range is not specified.")
    end


#    println(datetime_start)
#    println(datetime_end)
#    println(incflag_start)
#    println(incflag_end)
#error()

    # determine timestep
    # Currently, no flexibility...
    datetime_ctl_start = DateTime( gc.info["tdef"]["start"], dateformat"HH:MMzdduuuyyyy")
#    println( datetime_ctl_start )  # t = 1
#    ctl_datetime_start = replace( gc.info["tdef"]["start"], r"[](?<ymd>\d[^\d][^\d][^\d][\d][\d][\d][\d]#" => s"0\g<day>" )


    if gc.info["tdef"]["interval_unit"] == "hr"
        dstep = Dates.value( datetime_start - datetime_ctl_start ) / 1000 / 60 / 60 / gc.info["tdef"]["interval"]
        if dstep != floor(dstep)
	    error( "Date of start does not exist in the data: $date_start" )
	end
	t_start = ( ( incflag_start == true ) ? 1 : 2 ) + Int( dstep )
	println( t_start )

        dstep = Dates.value( datetime_end - datetime_ctl_start ) / 1000 / 60 / 60 / gc.info["tdef"]["interval"]
        if dstep != floor(dstep)
	    error( "Date of end does not exist in the data: $date_end" )
	end
	t_end = ( ( incflag_end == true ) ? 1 : 0 ) + Int( dstep )
	println( t_end )
    else
        error( "Non-supported time interval: ", gc.info["tdef"]["interval"] )
    end

    if t_start > t_end
        error( "Start timestep is later than end time step:", t_start, ", ", t_end )
    end

    if t_start < 1
        error( "Start timestep is less than 1: ", t_start )
    end

    if t_end > gc.info["tdef"]["num"]
        error("End timestep is greater than tdef (=", gc.info["tdef"]["num"], "): ", t_end)
    end
    # TODO: max(chsub_max_tstep) check

    #----- Input/output file management -----#
    
    # determine files and timestep range for each
    str_array  = Array{String}(undef,0)
    tmin_array  = Array{Int}(undef,0)
    tmax_array  = Array{Int}(undef,0)
    for chsub in gc.info["chsub"]
	( tmin, tmax ) = ( -1, -1 )

        if t_start <= chsub["start"]
	    tmin = chsub["start"]
        elseif t_start <= chsub["end"]
	    tmin = t_start
	end

        if t_end >= chsub["end"]
	    tmax = chsub["end"]
        elseif t_end >= chsub["start"]
	    tmax = t_end
	end

        if tmin > 0 && tmax > 0
            println(chsub)
            println( "(absolute) tmin:", tmin, "  tmax:", tmax )
	    tmin = tmin - chsub["start"] + 1  # absolute -> relative
	    tmax = tmax - chsub["start"] + 1  # absolute -> relative
            println( "(relative) tmin:", tmin, "  tmax:", tmax )
	    push!( str_array,  chsub["str"] )
	    push!( tmin_array, tmin )
	    push!( tmax_array, tmax )
        end
    end

    fid = FortranFile( out_fname, "w", access="direct", recl=4*gc.info["xdef"]["num"]*gc.info["ydef"]["num"]*gc.info["zdef"]["num"], convert=out_endian )

    tall = 0   # current absolute timestep - 1
    pos = 1
    for ( str, tmin, tmax ) in zip( str_array, tmin_array, tmax_array )
        println( tmin, ", ", tmax, ", ", str )
        dir = replace( gc.fname, r"/[^/]+$" => "" )
        fname = replace( gc.info["dset"], r"%ch" => str )
        fname = replace( fname, r"^\^" => dir * "/" )

        # read data
	for t = tmin:tmax
	    if( tall % t_int == 0 )
                println( t, "(", tall, ")" )
                v = ncread( fname, varname, start=[1,1,1,t], count=[-1,-1,-1,1] )
                write( fid, rec=pos, v )
		pos = pos + 1
	    end
	    tall = tall + 1
	end  # loop: t
    end  # loop: chsub
    
    close( fid )
end



end  # end of module


# export JULIA_REVISE_POLL=1

# (@v1.4) pkg> dev .

# julia> using Revise

# julia> using GradsCtl
