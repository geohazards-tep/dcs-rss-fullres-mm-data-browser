#!/bin/bash

# source the ciop functions (e.g. ciop-log, ciop-getparam)
source ${ciop_job_include}

# set the environment variables to use ESA SNAP toolbox
#export SNAP_HOME=$_CIOP_APPLICATION_PATH/common/snap
#export PATH=${SNAP_HOME}/bin:${PATH}
source $_CIOP_APPLICATION_PATH/gpt/snap_include.sh

# define the exit codes
SUCCESS=0
SNAP_REQUEST_ERROR=1
ERR_SNAP=2
ERR_NOPROD=3
ERR_NORETRIEVEDPROD=4
ERR_GETMISSION=5
ERR_GETDATA=6
ERR_WRONGINPUTNUM=7
ERR_GETPRODTYPE=8
ERR_WRONGPRODTYPE=9
ERR_GETPRODMTD=10
ERR_PCONVERT=11
ERR_UNPACKING=12
ERR_CONVERT=13
ERR_GDAL_CONF=14

# add a trap to exit gracefully
function cleanExit ()
{
    local retval=$?
    local msg=""

    case ${retval} in
        ${SUCCESS})               msg="Processing successfully concluded";;
        ${SNAP_REQUEST_ERROR})    msg="Could not create snap request file";;
        ${ERR_SNAP})              msg="SNAP failed to process";;
        ${ERR_NOPROD})            msg="No product reference input provided";;
        ${ERR_NORETRIEVEDPROD})   msg="Product not correctly downloaded";;
        ${ERR_GETMISSION})  	  msg="Error while retrieving mission name from product name or mission data not supported";;
        ${ERR_GETDATA})           msg="Error while discovering product";;
        ${ERR_WRONGINPUTNUM})     msg="Number of input products less than 1";;
        ${ERR_GETPRODTYPE})       msg="Error while retrieving product type info from input product name";;
        ${ERR_WRONGPRODTYPE})     msg="Product type not supported";;
	${ERR_GETPRODMTD})        msg="Error while retrieving metadata file from product";;
	${ERR_PCONVERT})          msg="PCONVERT failed to process";;
	${ERR_UNPACKING})         msg="Error unpacking input product";;
	${ERR_CONVERT})           msg="Error generating output product";;
	${ERR_GDAL_CONF})         msg="Error GDAL configuraiton file not found";;  
        *)                        msg="Unknown error";;
    esac

   [ ${retval} -ne 0 ] && ciop-log "ERROR" "Error ${retval} - ${msg}, processing aborted" || ciop-log "INFO" "${msg}"
   exit ${retval}
}

trap cleanExit EXIT

# function that checks the product type from the product name
function check_product_type() {
  
  local retrievedProduct=$1
  local productName=$( basename "$retrievedProduct" )
  local mission=$2

  if [ ${mission} = "Sentinel-1"  ] ; then
      #productName assumed like S1A_IW_TTT* where TTT is the product type to be extracted
      prodTypeName=$( echo ${productName:7:3} )
      [ -z "${prodTypeName}" ] && return ${ERR_GETPRODTYPE}
      # log the value, it helps debugging.
      # the log entry is available in the process stderr
      ciop-log "DEBUG" "Retrieved product type: ${prodTypeName}"
      [ $prodTypeName != "GRD" ] && return $ERR_WRONGPRODTYPE

  fi

  if [ ${mission} = "Sentinel-2"  ] ; then
      # productName assumed like S2A_TTTTTT_* where TTTTTT is the product type to be extracted  
      prodTypeName=$( echo ${productName:4:6} )
      [ -z "${prodTypeName}" ] && return ${ERR_GETPRODTYPE}
      # log the value, it helps debugging.
      # the log entry is available in the process stderr
      ciop-log "DEBUG" "Retrieved product type: ${prodTypeName}"
      [ $prodTypeName != "MSIL1C" ] && return $ERR_WRONGPRODTYPE
   
  fi

  if [ ${mission} = "Landsat-8" ]; then
      #Extract metadata file from Landsat
      filename="${retrievedProduct##*/}"; ext="${filename#*.}"
      ciop-log "INFO" "Retrieving product type from Landsat 8 product: $filename"
      ciop-log "INFO" "Product extension : $ext"
      if [[ "$ext" == "tar.bz" ]]; then
	ciop-log "INFO" "Running command: tar xjf $retrievedProduct ${filename%%.*}_MTL.txt" 
        tar xjf $retrievedProduct ${filename%%.*}_MTL.txt
	returnCode=$?
	[ $returnCode -eq 0 ] || return ${ERR_UNPACKING}
	[[ -e "${filename%%.*}_MTL.txt" ]] || return ${ERR_UNPACKING}
	prodTypeName=$(sed -n -e 's|^.*DATA_TYPE.*\"\(.*\)\".*$|\1|p' ${filename%%.*}_MTL.txt)
	rm -f ${filename%%.*}_MTL.txt
      fi
	
      ciop-log "INFO" "Retrieved product type: ${prodTypeName}"
      [[ "$prodTypeName" != "L1T" ]] && return $ERR_WRONGPRODTYPE

  fi

  if [ ${mission} = "Kompsat-2" ]; then
      if [[ -d "${retrievedProduct}" ]]; then
        prodTypeName=$(ls ${retrievedProduct}/*.tif | head -1 | sed -n -e 's|^.*_\(.*\).tif$|\1|p')
        [[ -z "$prodTypeName" ]] && ciop-log "ERROR" "Error prodTypeName is empty"
      else
        ciop-log "ERROR" "KOMPSAT-2 product was not unzipped"
	return ${ERR_UNPACKING}
      fi

      [[ "$prodTypeName" != "1G" ]] && return $ERR_WRONGPRODTYPE
  fi

  if [ ${mission} = "Kompsat-3" ]; then
      if [[ -d "${retrievedProduct}" ]]; then
        prodTypeName=$(ls ${retrievedProduct}/*.tif | head -1 | sed -n -e 's|^.*_\(.*\)_[A-Z].tif$|\1|p')
        [[ -z "$prodTypeName" ]] && ciop-log "ERROR" "Error prodTypeName is empty"
      else
        ciop-log "ERROR" "KOMPSAT-2 product was not unzipped"
        return ${ERR_UNPACKING}
      fi

      [[ "$prodTypeName" != "L1G" ]] && return $ERR_WRONGPRODTYPE
  fi

  if [ ${mission} = "Pleiades" ]; then

      ### !!!  %%TO-DO%% IDENTIFY pattern in the filename o contained metadata for product type check !!!!
       prodTypeName="Pleiades"
  fi

  if [[ "${mission}" == "Alos-2" ]]; then

       if [[ -d "${retrievedProduct}" ]]; then
          ALOS_ZIP=$(ls ${retrievedProduct} | egrep '^.*ALOS2.*.zip$')
       fi
       [[ -z "$ALOS_ZIP" ]] && ciop-log "ERROR" "Failed to get product type from : ${retrievedProduct}" 
 
       prodTypeName="$(unzip -p ${retrievedProduct}/$ALOS_ZIP summary.txt | sed -n -e 's|^.*_ProcessLevel=\"\(.*\)\".*$|\1|p')"
       [[ -z "$prodTypeName" ]] && ciop-log "ERROR" "Failed to get product type from : $ALOS_ZIP"

       [[ "$prodTypeName" != "1.5" ]] && return $ERR_WRONGPRODTYPE      
  fi

  if [[ "${mission}" == "TerraSAR-X" ]]; then
        ciop-log "INFO" "Retrieving product type from TerraSAR-X product: ${retrievedProduct}"
        if [[ -d "${retrievedProduct}" ]]; then
                tsx_xml=$(find ${retrievedProduct}/ -name '*SAR*.xml' | head -1 | sed 's|^.*\/||')
		prodTypeName="${tsx_xml:10:3}"
	elif [[ "${retrievedProduct##*.}" == "tar" ]]; then
		prodTypeName=$(tar tvf ${retrievedProduct} | sed -n -e 's|^.*\/||' -e 's|^.*_SAR__\(...\)_.*.xml$|\1|p')
	else
		ciop-log "ERROR" "Failed to get product type from : ${retrievedProduct}"
		return $ERR_WRONGPRODTYPE
	fi

	[[ "$prodTypeName" != "EEC" ]] && return $ERR_WRONGPRODTYPE

  fi

  if [[ "${mission}" == "SPOT-6" ]] || [[ "${mission}" == "SPOT-7"  ]]; then
        spot_xml=$(find ${retrievedProduct}/ -name 'DIM_SPOT?_MS_*.XML' | head -1 | sed 's|^.*\/||')
	prodTypeName="${spot_xml:29:3}"
        [[ "$prodTypeName" != "ORT" ]] && return $ERR_WRONGPRODTYPE
  fi

  if [[ "${mission}" == "UK-DMC2" ]]; then
	if [[ -d "${retrievedProduct}" ]]; then
		prodTypeName=$(ls ${retrievedProduct} | sed -n -e 's|^.*_\(.*\)\.tif$|\1|p')
		[[ -z "$prodTypeName" ]] && ciop-log "ERROR" "Failed to get product type from : ${retrievedProduct}"
	else
		ciop-log "ERROR" "Rerieved product ${retrievedProduct} is not a directory"
		return ${ERR_UNPACKING}
	fi
	
	[[ "$prodTypeName" != "L1T" ]] && return $ERR_WRONGPRODTYPE
  fi

  if [[ "${mission}" == "Resurs-P" ]]; then
	### !!! TO-DO: update once reference Resurs-P info, doc and samples are provided !!! ###
	prodTypeName="ResursP"
  fi

  if [[ "${mission}" == "Kanopus-V" ]]; then
	prodTypeName=${prodname:10:3}
	[[ "$prodTypeName" != "MSS" ]] && return $ERR_WRONGPRODTYPE
  fi

  # No support for Kompsat-5
  if [[ "${mission}" == "Kompsat-5" ]]; then
	return $ERR_WRONGPRODTYPE
  fi

  echo ${prodTypeName}
  return 0
}


# function that download and unzip data using the data catalougue reference
function get_data() {

  local ref=$1
  local target=$2
  local local_file
  local enclosure
  local res

  #get product url from input catalogue reference
  enclosure="$( opensearch-client -f atom "${ref}" enclosure)"
  # opensearh client doesn't deal with local paths
  res=$?
  [ $res -eq 0 ] && [ -z "${enclosure}" ] && return ${ERR_GETDATA}
  [ $res -ne 0 ] && enclosure=${ref}

  enclosure=$(echo "${enclosure}" | tail -1)

  #download data and get data name
  local_file="$( echo ${enclosure} | ciop-copy -f -O ${target} - 2> ${TMPDIR}/ciop_copy.stderr )"
  res=$?

  [ ${res} -ne 0 ] && return ${res}
  echo ${local_file}
}


# function that retrieves the mission data identifier from the product name 
function mission_prod_retrieval(){
	local mission=""
        local retrievedProduct=$1
        local prod_basename=$( basename "$retrievedProduct" )

        prod_basename_substr_3=${prod_basename:0:3}
        prod_basename_substr_4=${prod_basename:0:4}
        prod_basename_substr_5=${prod_basename:0:5}
	prod_basename_substr_9=${prod_basename:0:9}
        [ "${prod_basename_substr_3}" = "S1A" ] && mission="Sentinel-1"
        [ "${prod_basename_substr_3}" = "S1B" ] && mission="Sentinel-1"
        [ "${prod_basename_substr_3}" = "S2A" ] && mission="Sentinel-2"
        [ "${prod_basename_substr_3}" = "S2B" ] && mission="Sentinel-2"
        [ "${prod_basename_substr_3}" = "K5_" ] && mission="Kompsat-5"
        [ "${prod_basename_substr_3}" = "K3_" ] && mission="Kompsat-3"
	[ "${prod_basename_substr_3}" = "LC8" ] && mission="Landsat-8"
        [ "${prod_basename_substr_4}" = "LS08" ] && mission="Landsat-8"
        [ "${prod_basename_substr_4}" = "MSC_" ] && mission="Kompsat-2"
        [ "${prod_basename_substr_4}" = "FCGC" ] && mission="Pleiades"
	[ "${prod_basename_substr_5}" = "CHART" ] && mission="Pleiades"
        [ "${prod_basename_substr_5}" = "U2007" ] && mission="UK-DMC2"
	[ "${prod_basename_substr_5}" = "ORTHO" ] && mission="UK-DMC2"
        [ "${prod_basename}" = "Resurs-P" ] && mission="Resurs-P"
        [ "${prod_basename_substr_9}" = "KANOPUS_V" ] && mission="Kanopus-V"
        alos2_test=$(echo "${prod_basename}" | grep "ALOS2")
        [[ -z "${alos2_test}" ]] && alos2_test=$(ls "${retrievedProduct}" | grep "ALOS2")
        [ "${alos2_test}" = "" ] || mission="Alos-2"
	spot6_test=$(echo "${prod_basename}" | grep "SPOT6")
        [[ -z "${spot6_test}" ]] && spot6_test=$(ls "${retrievedProduct}" | grep "SPOT6")
        [ "${spot6_test}" = "" ] || mission="SPOT-6"
	spot7_test=$(echo "${prod_basename}" | grep "SPOT7")
        [[ -z "${spot7_test}" ]] && spot7_test=$(ls "${retrievedProduct}" | grep "SPOT7")
        [ "${spot7_test}" = "" ] || mission="SPOT-7"
	[ "${prod_basename_substr_3}" = "SO_" ] && mission="TerraSAR-X"
	[ "${prod_basename_substr_4}" = "dims" ] && mission="TerraSAR-X"
        
  	if [ "${mission}" != "" ] ; then
     	    echo ${mission}
  	else
     	    return ${ERR_GETMISSION}
  	fi
}


# function that generate the full res geotiff image from the original data product
function generate_full_res_tif (){
# function call generate_full_res_tif "${retrievedProduct}" "${mission}
  
  local retrievedProduct=$1
  local productName=$( basename "$retrievedProduct" )
  local mission=$2

  if [ ${mission} = "Sentinel-1"  ] ; then

    if [[ -d "${retrievedProduct}" ]]; then
      # loop on tiff products contained in the "measuremen" folder to reproject prior publishing
      find ${retrievedProduct}/ -name '*.tiff' > list
      for tifProd in $(cat list);
      do
          basename_tiff=$( basename $tifProd )
          
	  gdal_translate -scale -ot Byte -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "ALPHA=YES" "${tifProd}" temp-outputfile.tif
	  returnCode=$?
          [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
	
	  gdalwarp -ot Byte -srcnodata 0 -dstnodata 0 -dstalpha -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "ALPHA=YES" -t_srs EPSG:3857 temp-outputfile.tif ${TMPDIR}/${basename_tiff}
	  returnCode=$?
	  [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
	  rm -f temp-outputfile.tif

          #Add overviews
          gdaladdo -r average ${TMPDIR}/${basename_tiff} 2 4 8 16
          returnCode=$?
          [ $returnCode -eq 0 ] || return ${ERR_CONVERT}

	  mv ${TMPDIR}/${basename_tiff} ${OUTPUTDIR}/${basename_tiff}

	  # cleanup
          rm -rf $tifProd ${TMPDIR}/${basename_tiff}
      done
    else
      ciop-log "ERROR" "The retrieved product ${retrievedProduct} is not a directory or does not exist"
      return ${ERR_UNPACKING}
    fi

    # cleanup list
    rm list

  fi

  if [ ${mission} = "Sentinel-2"  ] ; then
      #get full path of S2 product metadata xml file
      # check if it is like S2?_*.xml
      # s2_xml=$(ls "${retrievedProduct}"/S2?_*.xml )
      s2_xml=$(find ${retrievedProduct}/ -name '*.xml' | egrep '^.*/S2[A-Z]?_.*.SAFE/S2[A-Z]?_[A-Z0-9]*.xml$') 
      # if it not like S2?_*.xml
      if [ $? -ne 0 ] ; then
          # check if it is like MTD_*.xml
          #s2_xml=$(ls "${retrievedProduct}"/MTD_*.xml )
          s2_xml=$(find ${retrievedProduct}/ -name '*.xml' | egrep '^.*/S2[A-Z]?_.*.SAFE/MTD_[A-Z0-9]*.xml$')
          #if it is neither like MTD_*.xml: return error
          [ $? -ne 0 ] && return $ERR_GETPRODMTD
      fi
      # create full resolution tif image with Red=B4 Green=B3 Blue=B2
      pconvert -b 4,3,2 -f tif -o ${OUTPUTDIR} ${s2_xml} &> /dev/null
      # check the exit code
      [ $? -eq 0 ] || return $ERR_PCONVERT

      outputfile=$(ls ${OUTPUTDIR} | egrep '^.*.tif$')
      tmp_outputfile="tmp_${outputfile}"
      mv ${OUTPUTDIR}/$outputfile ${OUTPUTDIR}/$tmp_outputfile
      gdal_translate -ot Byte -of GTiff -b 1 -b 2 -b 3 -scale -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" ${OUTPUTDIR}/$tmp_outputfile temp-outputfile.tif
      returnCode=$?
      [ $returnCode -eq 0 ] || return ${ERR_CONVERT}

      gdalwarp -ot Byte -t_srs EPSG:3857 -srcnodata 0 -dstnodata 0 -dstalpha -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" temp-outputfile.tif ${OUTPUTDIR}/$outputfile
      returnCode=$?
      [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
      rm -f temp-outputfile.tif

      #Remove temporary file
      rm -f ${OUTPUTDIR}/$tmp_outputfile
      rm -f ${OUTPUTDIR}/*.xml

      #Add overviews
      gdaladdo -r average ${OUTPUTDIR}/$outputfile 2 4 8 16
      returnCode=$?
      [ $returnCode -eq 0 ] || return ${ERR_CONVERT}            

  fi

  if [ ${mission} = "Landsat-8" ]; then

	ciop-log "INFO" "Creating full resolution tif for Landsat-8 product"
        #Check if downloaded product is compressed and extract it
        ext="${retrievedProduct##*/}"; ext="${ext#*.}"
	ciop-log "INFO" "Product extension is: $ext"
        if [[ "$ext" == "tar.bz" ]]; then
                ciop-log "INFO" "Extracting $retrievedProduct"
		mkdir -p ${retrievedProduct%/*}/temp
                cd ${retrievedProduct%/*}
                filename="${retrievedProduct##*/}"
                tar xjf $filename
                returnCode=$?
                [ $returnCode -eq 0 ] || return ${ERR_UNPACKING}

		#Define output filename
		outputfile="${filename%%.*}.tif"

		#Merge RGB bands in a single GeoTiff
		ciop-log "INFO" "Generate RGB TIF from LANDSAT-8 TIF bands"
		RED="${filename%%.*}_B4.TIF"
		GREEN="${filename%%.*}_B3.TIF"
		BLUE="${filename%%.*}_B2.TIF"
		
		gdal_merge.py -separate -n 0 -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" ${RED} ${GREEN} ${BLUE} -o ${retrievedProduct%/*}/temp/temp-rgb-outputfile.tif
		returnCode=$?
		[ $returnCode -eq 0 ] || return ${ERR_CONVERT}

		cd - 2>/dev/null

		ciop-log "INFO" "Apply reprojection and set alpha band"
		cd ${retrievedProduct%/*}/temp
		gdal_translate -ot Byte -of GTiff -b 1 -b 2 -b 3 -scale -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" temp-rgb-outputfile.tif temp-outputfile.tif
                returnCode=$?
                [ $returnCode -eq 0 ] || return ${ERR_CONVERT}

		gdalwarp -ot Byte -t_srs EPSG:3857 -srcnodata 0 -dstnodata 0 -dstalpha -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" temp-outputfile.tif ${outputfile}
		returnCode=$?
		[ $returnCode -eq 0 ] || return ${ERR_CONVERT}		
		# Remove temp files
		rm -f temp-outputfile.tif
		rm -f temp-rgb-outputfile.tif

		#Add overviews
		gdaladdo -r average ${outputfile} 2 4 8 16
		returnCode=$?
		[ $returnCode -eq 0 ] || return ${ERR_CONVERT}

		#Move output in output directory		
		mv ${outputfile} ${OUTPUTDIR}/

		cd - 2>/dev/null

		#Clean temp files and dirs
		rm -f ${retrievedProduct%/*}/*TIF 
		rm -f ${retrievedProduct%/*}/temp/*
		rmdir ${retrievedProduct%/*}/temp
        fi
  fi

  if [ ${mission} = "Kompsat-2" ]; then
	ciop-log "INFO" "Creating full resolution tif for KOMPSAT-2 product"
	if [[ -d "${retrievedProduct}" ]]; then
		cd ${retrievedProduct}
		#Select RGB bands
		RED=$(ls | egrep '^MSC_.*R_[0-9A-Zaz]{2}.tif$')
		GREEN=$(ls | egrep '^MSC_.*G_[0-9A-Zaz]{2}.tif$')
		BLUE=$(ls | egrep '^MSC_.*B_[0-9A-Zaz]{2}.tif$')
		PAN=$(ls | egrep '^MSC_[0-9]*_[0-9]*_[0-9]*P[PN][0-9]{2}_[0-9A-Zaz]{2}.tif$') 

		mkdir -p ${retrievedProduct}/temp

		outputfile="${retrievedProduct%/}"; outputfile="${retrievedProduct##*/}.tif"

		ciop-log "INFO" "Generate RGB TIF from Kompsat-2 TIF bands"
		gdal_merge.py -separate -n 0 -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" ${RED} ${GREEN} ${BLUE} -o ${retrievedProduct}/temp/temp-outputfile.tif
		returnCode=$?
		[ $returnCode -eq 0 ] || return ${ERR_CONVERT}	

		cd - 2>/dev/null

		ciop-log "INFO" "Apply reprojection and set alpha band"
		cd ${retrievedProduct}/temp

		gdal_translate -ot Byte -of GTiff -b 1 -b 2 -b 3 -scale -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" temp-outputfile.tif temp-outputfile2.tif
		returnCode=$?
                [ $returnCode -eq 0 ] || return ${ERR_CONVERT}

		gdalwarp -ot Byte -t_srs EPSG:3857 -srcnodata 0 -dstnodata 0 -dstalpha -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" temp-outputfile2.tif ${outputfile}
		returnCode=$?
		[ $returnCode -eq 0 ] || return ${ERR_CONVERT}
		rm -f temp-outputfile.tif 
		rm -f temp-outputfile2.tif

		#Add overviews
		gdaladdo -r average ${outputfile} 2 4 8 16
		returnCode=$?
		[ $returnCode -eq 0 ] || return ${ERR_CONVERT}

                mv ${outputfile} ${OUTPUTDIR}/

                cd - 2>/dev/null
	else
		ciop-log "ERROR" "The retrieved KOMPSAT-2 product is not a directory"
		return ${ERR_GETDATA}
	fi
  fi

  if [ ${mission} = "Kompsat-3" ]; then
        ciop-log "INFO" "Creating full resolution tif for KOMPSAT-3 product"
        if [[ -d "${retrievedProduct}" ]]; then
                cd ${retrievedProduct}
                #Select RGB bands
                RED=$(ls | egrep '^K3_.*_R.tif$')
                GREEN=$(ls | egrep '^K3_.*_G.tif$')
                BLUE=$(ls | egrep '^K3_.*_B.tif$')
                PAN=$(ls | egrep '^K3_.*_P.tif$')

                mkdir -p ${retrievedProduct}/temp

                outputfile="${retrievedProduct%/}"; outputfile="${retrievedProduct##*/}.tif"

                ciop-log "INFO" "Generate RGB TIF from Kompsat-3 TIF bands"
                gdal_merge.py -separate -n 0 -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" ${RED} ${GREEN} ${BLUE} -o ${retrievedProduct}/temp/temp-outputfile.tif
                returnCode=$?
                [ $returnCode -eq 0 ] || return ${ERR_CONVERT}

                cd - 2>/dev/null

                cd ${retrievedProduct}/temp
                
		gdal_translate -ot Byte -of GTiff -b 1 -b 2 -b 3 -scale -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" temp-outputfile.tif temp-outputfile2.tif
                returnCode=$?
                [ $returnCode -eq 0 ] || return ${ERR_CONVERT}

                gdalwarp -ot Byte -t_srs EPSG:3857 -srcnodata 0 -dstnodata 0 -dstalpha -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" temp-outputfile2.tif ${outputfile}
                returnCode=$?
                [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
                rm -f temp-outputfile.tif
                rm -f temp-outputfile2.tif

                #Add overviews
                gdaladdo -r average ${outputfile} 2 4 8 16
                returnCode=$?
                [ $returnCode -eq 0 ] || return ${ERR_CONVERT}

                mv ${outputfile} ${OUTPUTDIR}/

                cd - 2>/dev/null
        else
                ciop-log "ERROR" "The retrieved KOMPSAT-3 product is not a directory"
                return ${ERR_GETDATA}
        fi
  fi

  if [ ${mission} = "Pleiades" ]; then
	ciop-log "INFO" "Creating full resolution tif for Pleiades product"
        if [[ -d "${retrievedProduct}" ]]; then
                cd ${retrievedProduct}

		#Get image file
		pleiades_product=$(find ${retrievedProduct}/ -name 'IMG*.JP2')
		[[ -z "$pleiades_product" ]] && return ${ERR_CONVERT}

		#set output filename
		outputfile="${pleiades_product##*/}"; outputfile="${outputfile%.JP2}.tif"

		#Select RGB bands and convert to GeoTiff
		gdal_translate -ot Byte -of GTiff -b 3 -b 2 -b 1 -scale -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" ${pleiades_product} temp-outputfile.tif
		returnCode=$?
		[ $returnCode -eq 0 ] || return ${ERR_CONVERT}

		gdalwarp -ot Byte -t_srs EPSG:3857 -srcnodata 0 -dstnodata 0 -dstalpha -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" temp-outputfile.tif ${outputfile} 
                returnCode=$?
                [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
                rm -f temp-outputfile.tif

                #Add overviews
                gdaladdo -r average ${outputfile} 2 4 8 16
                returnCode=$?
                [ $returnCode -eq 0 ] || return ${ERR_CONVERT}

                mv ${outputfile} ${OUTPUTDIR}/

                cd - 2>/dev/null
        else
                ciop-log "ERROR" "The retrieved Pleiades product is not a directory"
                return ${ERR_GETDATA}
        fi
  fi

  if [ ${mission} = "SPOT-6" ] || [ ${mission} = "SPOT-7" ]; then
        ciop-log "INFO" "Creating full resolution tif for ${mission} product"
        if [[ -d "${retrievedProduct}" ]]; then
                cd ${retrievedProduct}

                #Get image file
		find ${retrievedProduct}/ -name 'IMG_SPOT?_MS_*.JP2' > list
      		for jp2prod in $(cat list);
      		do
		    # check if searched product exists 
                    [[ -z "$jp2prod" ]] && return ${ERR_CONVERT}
                    #set output filename
                    outputfile="${jp2prod##*/}"; outputfile="${outputfile%.JP2}.tif"

                    #Select RGB bands and convert to GeoTiff
                    gdal_translate -ot Byte -of GTiff -b 3 -b 2 -b 1 -scale -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" ${jp2prod} temp-outputfile.tif
                    returnCode=$?
                    [ $returnCode -eq 0 ] || return ${ERR_CONVERT}

                    gdalwarp -ot Byte -t_srs EPSG:3857 -srcnodata 0 -dstnodata 0 -dstalpha -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" temp-outputfile.tif ${outputfile}
                    returnCode=$?
                    [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
                    rm -f temp-outputfile.tif

                    #Add overviews
                    gdaladdo -r average ${outputfile} 2 4 8 16
                    returnCode=$?
                    [ $returnCode -eq 0 ] || return ${ERR_CONVERT}

                    mv ${outputfile} ${OUTPUTDIR}/
		done 

                cd - 2>/dev/null
        else
                ciop-log "ERROR" "The retrieved ${mission} product is not a directory"
                return ${ERR_GETDATA}
        fi
  fi


  if [[ "${mission}" == "Alos-2" ]]; then
	ciop-log "INFO" "Creating full resolution tif for ALOS-2 product"
	if [[ -d "${retrievedProduct}" ]]; then
		ALOS_ZIP=$(ls ${retrievedProduct} | egrep '^.*ALOS2.*.zip$')
		[[ -z "$ALOS_ZIP" ]] && ciop-log "ERROR" "Failed to get ALOS_ZIP"

		cd ${retrievedProduct}
		unzip $ALOS_ZIP
		for img in *.tif ; do
		   ciop-log "INFO" "Reprojecting ALOS-2 image: $img"
		   gdal_translate -scale -ot Byte -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "ALPHA=YES" $img temp-outputfile.tif
		   returnCode=$?
                   [ $returnCode -eq 0 ] || return ${ERR_CONVERT}		   
 
		   gdalwarp -ot Byte -srcnodata 0 -dstnodata 0 -dstalpha -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "ALPHA=YES" -t_srs EPSG:3857 temp-outputfile.tif ${OUTPUTDIR}/${img}
		   returnCode=$?
                   [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
                   rm -f temp-outputfile.tif

		   gdaladdo -r average ${OUTPUTDIR}/${img} 2 4 8 16
		   returnCode=$?
		   [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
		done
		cd -
        fi
  fi

  if [[ "${mission}" == "TerraSAR-X" ]]; then
	ciop-log "INFO" "Creating full resolution tif for TerraSAR-X product"
	if [[ -d "${retrievedProduct}" ]]; then
		#tsx_xml=$(find ${retrievedProduct}/ -name '*SAR*.xml' | head -1 | sed 's|^.*\/||')
		IMAGEDATA=$(find ${retrievedProduct} -name 'IMAGEDATA')
		if [[ -z "$IMAGEDATA" ]]; then 
			ciop-log "ERROR" "Failed to get IMAGEDATA dir"
			return ${ERR_CONVERT}
		fi
		cd $IMAGEDATA
		for img in *.tif ; do
			
			gdal_translate -scale -ot Byte -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "ALPHA=YES" $img temp-outputfile.tif
			returnCode=$?
                        [ $returnCode -eq 0 ] || return ${ERR_CONVERT}			

			gdalwarp -ot Byte -srcnodata 0 -dstnodata 0 -dstalpha -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "ALPHA=YES" -t_srs EPSG:3857 temp-outputfile.tif ${OUTPUTDIR}/${img}
			returnCode=$?
			[ $returnCode -eq 0 ] || return ${ERR_CONVERT}
			rm -f temp-outputfile.tif

	                gdaladdo -r average ${OUTPUTDIR}/${img} 2 4 8 16
        	        returnCode=$?
                	[ $returnCode -eq 0 ] || return ${ERR_CONVERT}
		done
		cd -
	elif [[ "${retrievedProduct##*.}" == "tar" ]]; then
		mkdir temp
		tar xf ${retrievedProduct} -C temp/
		returnCode=$?
		[ $returnCode -eq 0 ] || return ${ERR_CONVERT}
		IMAGEDATA=$(find $PWD/temp/ -name 'IMAGEDATA')		
                if [[ -z "$IMAGEDATA" ]]; then
                        ciop-log "ERROR" "Failed to get IMAGEDATA dir"
                        return ${ERR_CONVERT}
                fi
                cd $IMAGEDATA
                for img in *.tif ; do

			gdal_translate -scale -ot Byte -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "ALPHA=YES" $img temp-outputfile.tif
                        returnCode=$?
                        [ $returnCode -eq 0 ] || return ${ERR_CONVERT}

                        gdalwarp -ot Byte -srcnodata 0 -dstnodata 0 -dstalpha -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "ALPHA=YES" -t_srs EPSG:3857 temp-outputfile.tif ${OUTPUTDIR}/${img}
                        returnCode=$?
                        [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
                        rm -f temp-outputfile.tif

                        gdaladdo -r average ${OUTPUTDIR}/${img} 2 4 8 16
                        returnCode=$?
                        [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
                done
                cd -
		rm -rf temp
	fi
  fi

  if [[ "${mission}" == "UK-DMC2" ]]; then
	ciop-log "INFO" "Creating full resolution tif for UK-DMC2 product"
	if [[ -d "${retrievedProduct}" ]]; then
		tif_file=$(find ${retrievedProduct} -name '*.tif')

		ciop-log "INFO" "Processing Tiff file: $tif_file"
		
		gdal_translate -ot Byte -of GTiff -b 1 -b 2 -b 3 -scale -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" $tif_file temp-outputfile.tif
		returnCode=$?
                [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
			
		gdalwarp -ot Byte -t_srs EPSG:3857 -srcnodata 0 -dstnodata 0 -dstalpha -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" temp-outputfile.tif ${OUTPUTDIR}/${tif_file##*/}
		returnCode=$?
		[ $returnCode -eq 0 ] || return ${ERR_CONVERT}
		rm -f temp-outputfile.tif

		gdaladdo -r average ${OUTPUTDIR}/${tif_file##*/} 2 4 8 16
		returnCode=$?
		[ $returnCode -eq 0 ] || return ${ERR_CONVERT}
	else
		ciop-log "ERROR" "The retrieved product ${retrievedProduct} is not a directory"
		return ${ERR_CONVERT}
	fi
  fi

  if [[ "${mission}" == "Resurs-P" ]]; then
	ciop-log "INFO" "Creating full resolution tif for Resurs-P product"
        ### !!! TO-DO: update once reference Resurs-P info, doc and samples are provided !!! ###
	tif_file=$(find ${retrievedProduct} -name '*.tiff')

	ciop-log "INFO" "Processing Tiff file: $tif_file"
	ciop-log "INFO" "Running gdal_translate"
	outputfile=${tif_file##*/}; outputfile=${outputfile%.tiff}.tif
	gdal_translate -ot Byte -of GTiff -b 3 -b 2 -b 1 -scale -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" $tif_file ${TMPDIR}/${outputfile}
	returnCode=$?
	[ $returnCode -eq 0 ] || return ${ERR_CONVERT}

	ciop-log "INFO" "Running gdalwarp"
	gdalwarp -ot Byte -t_srs EPSG:3857 -srcnodata 0 -dstnodata 0 -dstalpha -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" ${TMPDIR}/${outputfile} ${OUTPUTDIR}/${outputfile}
	returnCode=$?
	[ $returnCode -eq 0 ] || return ${ERR_CONVERT}
	rm -f ${TMPDIR}/${outputfile}

	gdaladdo -r average ${OUTPUTDIR}/${outputfile} 2 4 8 16
        returnCode=$?
        [ $returnCode -eq 0 ] || return ${ERR_CONVERT}

  fi

  if [[ "${mission}" == "Kanopus-V" ]]; then
        ciop-log "INFO" "Creating full resolution tif for Kanopus-V product"
        ### !!! TO-DO: update once reference Kanopus-V info, doc and samples are provided !!! ###
        tif_file=$(find ${retrievedProduct} -name '*.tiff')

        ciop-log "INFO" "Processing Tiff file: $tif_file"
        ciop-log "INFO" "Runing gdal_translate"
        outputfile=${tif_file##*/}; outputfile=${outputfile%.tiff}.tif
        gdal_translate -ot Byte -of GTiff -b 3 -b 2 -b 1 -scale -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" $tif_file ${TMPDIR}/${outputfile}
        returnCode=$?
        [ $returnCode -eq 0 ] || return ${ERR_CONVERT}

        ciop-log "INFO" "Runing gdalwarp"
        gdalwarp -ot Byte -t_srs EPSG:3857 -srcnodata 0 -dstnodata 0 -dstalpha -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" ${TMPDIR}/${outputfile} ${OUTPUTDIR}/${outputfile}
        returnCode=$?
        [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
	rm -f ${TMPDIR}/${outputfile}
	
	gdaladdo -r average ${OUTPUTDIR}/${outputfile} 2 4 8 16
        returnCode=$?
        [ $returnCode -eq 0 ] || return ${ERR_CONVERT}

 
  fi

  return 0

}


function main() {

    #get input product list and convert it into an array
    local -a inputfiles=($@)

    #get the number of products to be processed
    inputfilesNum=$#

    # check if number of products is at least 1  
    [ "$inputfilesNum" -lt "1" ] && exit $ERR_WRONGINPUTNUM
   
    # log the value, it helps debugging.
    # the log entry is available in the process stderr
    ciop-log "DEBUG" "Number of input products: ${inputfilesNum}"
    let "inputfilesNum-=1"    
    
    # loop on input product to generate and publish full res geotiff
    for prodIndex in `seq 0 $inputfilesNum`;
    do
	### GET CURRENT DATA PRODUCT

        #current product
        currentProduct=${inputfiles[$prodIndex]}
	# run a check on the value, it can't be empty
    	[ -z "$currentProduct" ] && exit $ERR_NOPROD
	# log the value, it helps debugging.
    	# the log entry is available in the process stderr
    	ciop-log "DEBUG" "The product reference to be used is: ${currentProduct}"
	# report product retrieving activity in log
    	ciop-log "INFO" "Retrieving ${currentProduct}"
    	# retrieve product to the local temporary folder TMPDIR provided by the framework (this folder is only used by this process)
    	# the utility returns the local path of the retrieved product
    	retrievedProduct=$( get_data "${currentProduct}" "${TMPDIR}" )
    	if [ $? -ne 0  ] ; then
            cat ${TMPDIR}/ciop_copy.stderr
            return $ERR_NORETRIEVEDPROD
    	fi
    	prodname=$( basename "$retrievedProduct" )
	# report activity in the log
    	ciop-log "INFO" "Product correctly retrieved: ${prodname}"
	
	### EXTRACT MISSION IDENTIFIER

	# report activity in the log
        ciop-log "INFO" "Retrieving mission identifier from product name"
	mission=$( mission_prod_retrieval "${retrievedProduct}")
        [ $? -eq 0 ] || return ${ERR_GETMISSION}
        # log the value, it helps debugging.
        # the log entry is available in the process stderr
	ciop-log "INFO" "Retrieved mission identifier: ${mission}"

	### PRODUCT TYPE CHECK
	
	# report activity in the log
        ciop-log "INFO" "Checking product type from product name"
        #get product type from product name
        prodType=$( check_product_type "${retrievedProduct}" "${mission}" )
        returnCode=$?
	[ $returnCode -eq 0 ] || return $returnCode
        # log the value, it helps debugging.
        # the log entry is available in the process stderr
        ciop-log "INFO" "Retrieved product type: ${prodType}"
        
	### FULL RES GEOTIFF GENERATION AND PUBLISH
	
	# report activity in the log
        ciop-log "INFO" "Creating full resolution tif product(s) for ${prodname}"
	generate_full_res_tif "${retrievedProduct}" "${mission}"
	returnCode=$?
        [ $returnCode -eq 0 ] || return $returnCode
        # Publish results 
	# NOTE: it is assumed that the "generate_full_res_tif" function always provides results in $OUTPUTDIR 		
	# report activity in the log    
	ciop-log "INFO" "Publishing results for ${prodname}"
        ciop-publish -m ${OUTPUTDIR}/*.*
	
	#cleanup 
   	rm -rf ${retrievedProduct} ${OUTPUTDIR}/*.*

    done

    #cleanup
    rm -rf ${TMPDIR}

    return ${SUCCESS}
}

# create the output folder to store the output products and export it
mkdir -p ${TMPDIR}/output
export OUTPUTDIR=${TMPDIR}/output
# debug flag setting
export DEBUG=1

# loop on input file to create a product array that will be processed by the main process 
declare -a inputfiles
while read inputfile; do
    inputfiles+=("${inputfile}") # Array append
done
# run main process
main ${inputfiles[@]}
res=$?
[ ${res} -ne 0 ] && exit ${res}

exit $SUCCESS

