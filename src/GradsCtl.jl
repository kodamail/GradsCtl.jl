module GradsCtl

using NetCDF
using FortranFiles
using Dates

include("GradsCtlFile.jl")

export GradsCtlFile

export gcopen
export gcslice
export gcslicewrite  # alias of gcslice, for compatibility


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

        # VARS
        if mul_status == "vars"
            if occursin( r"^endvars"i, words[1] )
	        mul_status = ""
		continue
	    end
            varname = words[1]
            tmp = split( words[1], "=>", keepempty=false )
	    if length(tmp) > 1
                push!( gc.info["vars"]["elem"], Dict(
                          "varname"      => tmp[1],
	                  "gradsvarname" => tmp[2],
			  "scale_factor" => 1.0f0,
			  "add_offset"   => 0.0f0 ) )
            end
	    continue

        # XDEF/YDEF/ZDEF
        elseif mul_status == "xdef" || mul_status == "ydef" || mul_status == "zdef" 
            if occursin( r"^[^0-9-.]", words[1] )
	        mul_status = ""
	    else
               for word in words
                    push!( gc.info[mul_status]["levels"], parse( Float32, word ) )
	        end
	        continue
	    end
	    
        # EDEF
        elseif mul_status == "edef" 
            if occursin( r"^endedef"i, words[1] )
	        mul_status = ""
		continue
	    end
            push!( gc.info["edef"]["ensname"], words[1] )
            push!( gc.info["edef"]["length"],  parse( Int, words[2] ) )
            push!( gc.info["edef"]["start"],  words[3] )
            continue
	end

        #----- single-line or start of muti-line statement -----#
	mul_status = ""

        # DSET
        if occursin( r"^dset"i, words[1] )
	    gc.info["dset"] = words[2]
	    continue
	end

        # DTYPE
        if occursin( r"^dtype"i, words[1] )
	    gc.info["dtype"] = words[2]
            continue
	end

        # INDEX
        if occursin( r"^index"i, words[1] )
	    gc.info["index"] = words[2]
            continue
	end

        # STNMAP
        if occursin( r"^stnmap"i, words[1] )
	    gc.info["stnmap"] = words[2]
            continue
	end

        # TITLE
        if occursin( r"^title"i, words[1] )
	    gc.info["title"] = words[2]
            continue
	end

        # UNDEF
        if occursin( r"^undef"i, words[1] )
	    gc.info["undef"] = parse( Float32, replace( words[2], r"f$" => "" ) )
            continue
	end

        # XDEF/YDEF/ZDEF
        if occursin( r"^xdef|ydef|zdef$"i, words[1] )
	    dim = lowercase( words[1] )
            if tryparse( Int, words[2] ) == nothing
	        gc.info[dim]["varname"] = words[2]
                popfirst!( words )
	    end
            gc.info[dim]["num"]  = parse( Int, words[2] )
            gc.info[dim]["type"] = lowercase( words[3] )
	    if gc.info[dim]["type"] == "linear"
                gc.info[dim]["start"]    = parse( Float32, words[4] )
                gc.info[dim]["interval"] = parse( Float32, words[5] )
	    elseif gc.info[dim]["type"] == "levels"
                for word in words[4:end]
                    push!( gc.info[dim]["levels"], parse( Float32, word ) )
	        end
                mul_status = dim
                continue
	    else
                error( "Fail to analyze $dim: \"$line\"" )
	    end
            continue
	end

        # EDEF
        if occursin( r"^edef$"i, words[1] )
            gc.info["edef"]["num"]  = parse( Int, words[2] )
	    if length(words) < 3
	        mul_status = "edef"
		
	    elseif occursin( r"^names$"i, words[3] )
	        for word in words[4:end]
	            push!( gc.info["edef"]["ensname"], word )
	            push!( gc.info["edef"]["length"], -1 )
	            push!( gc.info["edef"]["start"], "" )
		end
	    else
                error( "Fail to analyze edef" )
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

	# OPTIONS
        if occursin( r"^options"i, words[1] )
            for word in words[2:end]
		if occursin( r"^big_endian"i, word )
                    gc.info["options"]["endian"] = "big-endian"
		    continue
		elseif occursin( r"^little_endian"i, word )
                    gc.info["options"]["endian"] = "little-endian"
		    continue
                elseif occursin( r"^template"i, word )
                    gc.info["options"]["template"] = true
		    continue
                elseif occursin( r"^yrev"i, word )
                    gc.info["options"]["yrev"] = true
		    continue
                elseif occursin( r"^zrev"i, word )
                    gc.info["options"]["zrev"] = true
		    continue
                elseif occursin( r"^365_day_calendar"i, word )
                    gc.info["options"]["365_day_calendar"] = true
		    continue
		end
                error( "\"$word\" is not supported in $words[1]")
            end
	    continue
	end

	# CHSUB
        if occursin( r"^chsub"i, words[1] )
           push!( gc.info["chsub"], Dict(
	       "start" => parse( Int, words[2]),
	       "end"   => parse( Int, words[3]),
	       "str"   => words[4] ) )
	       
	   # Check continuity of timestep
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

    #----- Check consistency -----#
    if length( gc.info["chsub"] ) > 0
        if gc.info["tdef"]["num"] != gc.info["chsub"][end]["end"]
	    println( stderr, "Warning: The maximum timestep of CHSUB (", gc.info["chsub"][end]["end"], ") does not match the number of TDEF (", gc.info["tdef"]["num"], ")." )
	end
    end
    
    #----- Determine the data type (flat binary, NetCDF, ...) -----#
    if occursin( r"\.nc$"i, gc.info["dset"] )
        gc.ftype = "NetCDF"
    else
        gc.ftype = ""  # flat binary
    end
    
    #----- Additional analysis when the data are in NetCDF format -----#
    if gc.ftype == "NetCDF"
        # Generate data file name for tstep=1
        dir = replace( gc.fname, r"/[^/]+$" => "" )
        dat_fname = gc.info["dset"]
        dat_fname = replace( dat_fname, r"^\^" => "$dir/" )
        dat_fname = replace( dat_fname, "%ch" => gc.info["chsub"][1]["str"] )
	#TODO: %y4, %m2, ...

        # Read metadata
        nc = NetCDF.open( dat_fname, mode=NC_NOWRITE )
        gc.info["xdef"]["num"] = size( nc["lon"], 1 )
        gc.info["ydef"]["num"] = size( nc["lat"], 1 )
        gc.info["zdef"]["num"] = size( nc["lev"], 1 )

        # Read variable name unless stored yet
	if size( gc.info["vars"]["elem"], 1 ) == 0
            for varname in keys(nc)
	        if occursin( r"^lon|longitude|lat|latitude|lev|level|time$"i, varname )
		    continue
		end
                push!( gc.info["vars"]["elem"], Dict(
                          "varname"      => varname,
	                  "gradsvarname" => varname,
			  "scale_factor" => 1.0f0,
			  "add_offset"   => 0.0f0 ) )
            end

	end
	
        # varname
	for i=1:size(gc.info["vars"]["elem"],1)
	    tmp = NetCDF.ncgetatt( dat_fname, gc.info["vars"]["elem"][i]["varname"], "scale_factor" )
	    println( stderr, gc.info["vars"]["elem"][i] )
	    if tmp != nothing
	        gc.info["vars"]["elem"][i]["scale_factor"] = tmp
	    end
	    tmp = NetCDF.ncgetatt( dat_fname, gc.info["vars"]["elem"][i]["varname"], "add_offset" )
	    if tmp != nothing
	        gc.info["vars"]["elem"][i]["add_offset"] = tmp
	    end
	    tmp = NetCDF.ncgetatt( dat_fname, gc.info["vars"]["elem"][i]["varname"], "_FillValue" )
	    if tmp != nothing
	        gc.info["vars"]["elem"][i]["_FillValue"] = tmp
	    end	    
	end

    end

    return gc
end


"""
    gcslice( gc, varname, out_fname, ...

Write sliced data to a file
"""
function gcslice( gc::GradsCtlFile,
    	          varname::String,
    	          out_fname   ::String="";
		  #----- optional -----#
		  # time
		  ymd_range   ::String="",
		  cal_range   ::String="",
		  t_int       ::Integer=1,
		  datetime_start::DateTime=DateTime(-1),
		  datetime_end  ::DateTime=DateTime(-1),
		  # output file
		  out_endian  ::String="native"    # "little-endian" or "big-endian"
		)

    #-----Analyze argument -----#
#    println(datetime_start)

    # resolve variable
    scale_factor = 1.0f0
    add_offset = 0.0f0
    undef_val = ""
    for elem in gc.info["vars"]["elem"]
        if varname == elem["gradsvarname"]
	    varname      = elem["varname"]
	    scale_factor = elem["scale_factor"]
	    add_offset   = elem["add_offset"]
	    undef_val    = elem["_FillValue"]
	    break
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

    elseif datetime_start >= DateTime(0) && datetime_end >= datetime_start
        incflag_start = true
        incflag_end   = true
    else
	error("Time range is not specified.")
    end

#    println(datetime_start)
#    println(datetime_end)
#    println(incflag_start)
#    println(incflag_end)
#error()

    #----- Time management -----#
    
    # determine timestep
    tmp = gc.info["tdef"]["start"]
    if occursin( r"^[a-zA-Z]{3}\d+$", tmp )  # e.g. jan2010
        tmp = "01" * tmp      # assume day=01
    end
    if occursin( r"^\d+[a-zA-Z]{3}\d+$", tmp )  # e.g. 01jan2010
        tmp = "00:00z" * tmp  # assume 00:00
    end
    if occursin( r"^\d+z\d+[a-zA-Z]{3}\d+$"i, tmp )  # e.g. 06z01jan2010
        tmp = replace( tmp, r"(?<hr>\d+)z"i => s"\g<hr>:00z" )  # assume min=00
    end
    datetime_ctl_start = DateTime( tmp, dateformat"HH:MMzdduuuyyyy")  # time at t=1

    if gc.info["tdef"]["interval_unit"] == "hr"
        dstep = Dates.value( datetime_start - datetime_ctl_start ) / 1000 / 60 / 60 / gc.info["tdef"]["interval"]
#        println(dstep)
	if dstep == ceil(dstep) && incflag_start == false
            dstep = ceil(dstep) + 1
	else
            dstep = ceil(dstep)
	end
#	println(dstep)
#	error()
#        if dstep != floor(dstep)
#	    error( "Date of start does not exist in the data: $date_start" )
#	end
#	t_start = ( ( incflag_start == true ) ? 1 : 2 ) + Int( dstep )
	t_start = Int( dstep ) + 1
	println( stderr, t_start )

        dstep = Dates.value( datetime_end - datetime_ctl_start ) / 1000 / 60 / 60 / gc.info["tdef"]["interval"]
#        println(dstep)
	if dstep == floor(dstep) && incflag_end == false
            dstep = floor(dstep) - 1
	else
            dstep = floor(dstep)
	end
#	println(dstep)
#	error()
#        if dstep != floor(dstep)
#	    error( "Date of end does not exist in the data: $date_end" )
#	end
#	t_end = ( ( incflag_end == true ) ? 1 : 0 ) + Int( dstep )
	t_end = Int( dstep ) + 1
	println( stderr, t_end )
    else
        error( "Non-supported time interval: ", gc.info["tdef"]["interval"] )
    end

    if t_start > t_end
        error( "Start timestep (", t_start, ") is later than end time step (", t_end, ")" )
    end

    if t_start < 1
        error( "Start timestep (", t_start, ") is less than 1: " )
    end

    if t_end > gc.info["tdef"]["num"]
        error( "End timestep (", t_end, ") is greater than tdef (", gc.info["tdef"]["num"], ")." )
    end

    if length( gc.info["chsub"] ) > 0
        if t_end > gc.info["chsub"][end]["end"]
	    error( "End timestep (", t_end, ") is greater than the maximum timestep of CHSUB (", gc.info["chsub"][end]["end"], ")." )
	end
    end

    #----- Input/output file management -----#
    
    if length( gc.info["chsub"] ) > 0
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
                println( stderr, chsub )
                println( stderr, "(absolute) tmin:", tmin, "  tmax:", tmax )
            tmin = tmin - chsub["start"] + 1  # absolute -> relative
	        tmax = tmax - chsub["start"] + 1  # absolute -> relative
                println( stderr, "(relative) tmin:", tmin, "  tmax:", tmax )
                push!( str_array,  chsub["str"] )
	        push!( tmin_array, tmin )
	        push!( tmax_array, tmax )
            end
        end
    else
        error( "Non-supported time type" )
    end
    
    #----- Input/output files -----#

    if out_fname == ""
        action = "array"
	#vret = Array{Int16}( undef, gc.info["xdef"]["num"], gc.info["ydef"]["num"], gc.info["zdef"]["num"], 0 )
	#vret = Array{Int16}( undef, 0 )
        vret = Array{Float32}( undef, 0 )
#        vtmp = Array{Float32}( undef, gc.info["xdef"]["num"], gc.info["ydef"]["num"], gc.info["zdef"]["num"], 1 )
	
	println( stderr, "ok: ", size(vret) )
    else
        action = "write"
        fid_out = FortranFile( out_fname, "w", access="direct", recl=4*gc.info["xdef"]["num"]*gc.info["ydef"]["num"]*gc.info["zdef"]["num"], convert=out_endian )
    end

    v = zeros( Float32, gc.info["xdef"]["num"]*gc.info["ydef"]["num"]*gc.info["zdef"]["num"] )
    tall = 1   # current absolute timestep
    pos = 1
    for ( str, tmin, tmax ) in zip( str_array, tmin_array, tmax_array )
        dir = replace( gc.fname, r"/[^/]+$" => "" )
        fname = replace( gc.info["dset"], r"%ch" => str )
        fname = replace( fname, r"^\^" => dir * "/" )
        println( stderr, tmin, ", ", tmax, ", ", fname )

	for t = tmin:tmax
	    if (tall-1) % t_int == 0

                # read
                println( stderr, t, "(", tall, ")" )
		if gc.ftype == "NetCDF"
                    v = ncread( fname, varname, start=[1,1,1,t], count=[-1,-1,-1,1] )
		else
                    fid_in = FortranFile( fname, "r", access="direct", recl=4*gc.info["xdef"]["num"]*gc.info["ydef"]["num"]*gc.info["zdef"]["num"], convert=gc.info["options"]["endian"] )
		    read( fid_in, rec=t, v )
		end
		
		#println( typeof(v), " : ", size(v) )
		# scale/offset
		if scale_factor != 1.0 || add_offset != 0.0
		    vtmp = Float32.( v .* scale_factor .+ add_offset )
		    vtmp[v .== undef_val] .= -9.99f+34
		    v = copy(vtmp)
#		    println(typeof(v), " : ", size(v))
		end
#    scale_factor = 1.0
#    add_offset = 0.0
#    undef_val = ""
                # write/store
		if action == "array"
		    #cat( vret, v; dims=4 )
		    append!( vret, reshape(v,:) )
		    #println( typeof(vret), " : ", size(vret) )
		elseif action == "write"
                    write( fid_out, rec=pos, v )
		end
		pos = pos + 1
	    end
	    tall = tall + 1
	end  # loop: t
    end  # loop: chsub

    if action == "array"
        return reshape( vret, gc.info["xdef"]["num"], gc.info["ydef"]["num"], gc.info["zdef"]["num"], : )
    elseif action == "write"
        close( fid_out )
    end
end

gcslicewrite = gcslice  # alias


end  # end of module


# export JULIA_REVISE_POLL=1

# (@v1.4) pkg> dev .

# julia> using Revise

# julia> using GradsCtl
