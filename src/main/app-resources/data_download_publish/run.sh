#!/bin/bash

# source the ciop functions (e.g. ciop-log, ciop-getparam)
source ${ciop_job_include}

# set the environment variables to use ESA SNAP toolbox
source $_CIOP_APPLICATION_PATH/gpt/snap_include.sh
# set the environment variables to use ORFEO toolbox
source $_CIOP_APPLICATION_PATH/otb/otb_include.sh
## put /opt/anaconda/bin ahead to the PATH list to ensure gdal to point to the anaconda installation dir
export PATH=/opt/anaconda/bin:${PATH}

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
ERR_WRONGPOLARIZATION=14
ERR_METADATA=15
ERR_OTB=16
ERR_PAN=17
ERR_GET_BANDS_NUM=18


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
        ${ERR_WRONGPOLARIZATION}) msg="Error in input product polarization";;
        ${ERR_METADATA}) 	  msg="Error while generating metadata";;
        ${ERR_OTB})          	  msg="Orfeo Toolbox failed to process";;
	${ERR_PAN})               msg="The Panchromatic product of this mission is not supported";;
        ${ERR_GET_BANDS_NUM})     msg="Error while getting number of bands from tif product";;
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
      #productName assumed like S1A_IW_TTTT_* where TTTT is the product type to be extracted
      prodTypeName=$( echo ${productName:7:4} )
      [ -z "${prodTypeName}" ] && return ${ERR_GETPRODTYPE}
      if [ $prodTypeName != "GRDH" ] && [ $prodTypeName != "GRDM" ]; then
          return $ERR_WRONGPRODTYPE
      fi
  fi

  if [ ${mission} = "Sentinel-2"  ] ; then
      #filename="${retrievedProduct##*/}"; ext="${filename#*.}"	
      ciop-log "INFO" "retrieved product is ${retrievedProduct}"
        
 	#tar xf $retrievedProduct
      full_name=($( (find $retrievedProduct -type d -name "S2*.SAFE") ))
      check_name=$( basename "$full_name" )

      ciop-log "INFO" "Fullname is $check_name"
      prodTypeName=${check_name:4:6}
      ciop-log "INFO" "Product type is ${prodTypeName}"
      ciop-log "DEBUG" "Retrieved product type: ${prodTypeName}"
      if [ $prodTypeName != "MSIL1C" ] && [[ "$prodTypeName" != "MSIL2A" ]] ; then
	 return $ERR_WRONGPRODTYPE
      fi
  fi

  if [ ${mission} = "Sentinel-3" ] ; then
        ciop-log "INFO" "retrieved product is ${productName}"

	prodTypeName=$( echo ${productName:9:3} )
        ciop-log "INFO" "retrieved product is type: ${prodTypeName}"
        if [ $prodTypeName != "EFR" ] && [ $prodTypeName != "ERR" ]; then
           return $ERR_WRONGPRODTYPE
        fi

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
          [ $returnCode -eq 0 ] || return ${ERR_GETPRODTYPE}
          [[ -e "${filename%%.*}_MTL.txt" ]] || return ${ERR_GETPRODTYPE}
          prodTypeName=$(sed -n -e 's|^.*DATA_TYPE.*\"\(.*\)\".*$|\1|p' ${filename%%.*}_MTL.txt)
          rm -f ${filename%%.*}_MTL.txt
      elif
          [[ "$ext" == "tar" ]]; then
          ciop-log "INFO" "Running command: tar xf $retrievedProduct *_MTL.txt"
          tar xf $retrievedProduct *_MTL.txt
          returnCode=$?
          [ $returnCode -eq 0 ] || return ${ERR_GETPRODTYPE}
          prodTypeName=$(sed -n -e 's|^.*DATA_TYPE.*\"\(.*\)\".*$|\1|p' *_MTL.txt)
          rm -f *_MTL.txt
      else
          metadatafile=$(ls ${retrievedProduct}/vendor_metadata/*_MTL.txt)
          [[ -e "${metadatafile}" ]] || return ${ERR_GETPRODTYPE}
          prodTypeName=$(sed -n -e 's|^.*DATA_TYPE.*\"\(.*\)\".*$|\1|p' ${metadatafile})
      fi
      # log the value, it helps debugging.
      # the log entry is available in the process stderr
      ciop-log "DEBUG" "Retrieved product type: ${prodTypeName}"
      if [[ "$prodTypeName" != "L1TP" ]] && [[ "$prodTypeName" != "L1T" ]] && [[ "$prodTypeName" != "L1GT" ]] ; then
          return $ERR_WRONGPRODTYPE
      fi
  fi

  if [ ${mission} = "Kompsat-2" ]; then
      if [[ -d "${retrievedProduct}" ]]; then
        prodTypeName=$(find ${retrievedProduct} -name '*.tif' | head -1 | sed -n -e 's|^.*_\(.*\).tif$|\1|p')
        [[ -z "$prodTypeName" ]] && ciop-log "ERROR" "Error prodTypeName is empty"
      else
        ciop-log "ERROR" "KOMPSAT-2 product was not unzipped"
	return ${ERR_UNPACKING}
      fi
      # Only L1G are supported
      [[ "$prodTypeName" != "1G" ]] && return $ERR_WRONGPRODTYPE
  fi

  if [ ${mission} = "Kompsat-3" ]; then
      #naming convention K3_”Time”_”OrbNo”_"PassNo"_”ProcLevel”
      prodTypeName=${productName:(-3)}
      # Only L1G is supported
      if [[ "$prodTypeName" != "L1G" ]]; then 
          return $ERR_WRONGPRODTYPE
      fi
  fi

  if [ ${mission} = "Pleiades" ]; then
      # Get multispectral metadata file
      metadatafile=$(find ${retrievedProduct}/ -name 'DIM_*MS_*.XML')
      [[ -e "${metadatafile}" ]] || return ${ERR_GETPRODTYPE}
      prodTypeName=$(sed -n -e 's|^.*<PROCESSING_LEVEL>\(.*\)</PROCESSING_LEVEL>$|\1|p' ${metadatafile})
      [[ "$prodTypeName" != "ORTHO" ]] && return $ERR_WRONGPRODTYPE
  fi

  if [[ "${mission}" == "Alos-2" ]]; then
       prodTypeName=""
       # check if ALOS2 product is a folder
       if [[ -d "${retrievedProduct}" ]]; then
	   # check if ALOS2 folder contains a zip file
           ALOS_ZIP=$(ls ${retrievedProduct} | egrep '^.*ALOS2.*.zip$')
           # if doesn't contain a zip it should be already uncompressed -> search summary file into the folder
	   if [[ -z "$ALOS_ZIP" ]]; then
	       prodTypeName="$( cat ${retrievedProduct}/summary.txt | sed -n -e 's|^.*_ProcessLevel=\"\(.*\)\".*$|\1|p')"
 	   # extract summary file from compressed archive 
           else
               prodTypeName="$(unzip -p ${retrievedProduct}/$ALOS_ZIP summary.txt | sed -n -e 's|^.*_ProcessLevel=\"\(.*\)\".*$|\1|p')"
           fi
       fi
       [[ -z "$prodTypeName" ]] && ciop-log "ERROR" "Failed to get product type from : $retrievedProduct"
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
        spot_xml=$(find ${retrievedProduct}/ -name 'DIM_SPOT?_*MS_*.XML')
	prodTypeName=$(sed -n -e 's|^.*<DATASET_TYPE>\(.*\)</DATASET_TYPE>$|\1|p' ${spot_xml})
        [[ "$prodTypeName" != "RASTER_ORTHO" ]] && return $ERR_WRONGPRODTYPE
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
	prodTypeName="MSS"
  fi

  if [[ "${mission}" == "Kanopus-V" ]]; then
        mss_test=$(echo "${productName}" | grep "MSS")
	[[ "$mss_test" != "" ]] && prodTypeName="MSS"  || return $ERR_WRONGPRODTYPE
  fi

  if [[ "${mission}" == "Kompsat-5" ]]; then
        #naming convention <K5>_<YYYYMMDDhhmmss>_<tttttt>_<nnnnn>_<o>_<MM><SS>_<PP>_<LLL> where LLL is the processing level
	prodTypeName=${productName:47:3}
        [[ "$prodTypeName" != "L1D" ]] && return $ERR_WRONGPRODTYPE
  fi

  if [[ "${mission}" == "Radarsat-2" ]]; then
      #naming convention <RS2_BeamMode_Date_Time_Polarizations_ProcessingLevel>
      prodTypeName=${productName:(-3)}
      [[ "$prodTypeName" != "SGF" ]] && return $ERR_WRONGPRODTYPE    
  fi

  if [[ "${mission}" == "GF2" ]]; then
      filename="${retrievedProduct##*/}"; ext="${filename#*.}"
      # assumption is that the product has .tar extension
      if  [[ "$ext" == "tar" ]]; then
          ciop-log "INFO" "Running command: tar xf $retrievedProduct *MSS2.xml"
          tar xf $retrievedProduct *MSS2.xml
          returnCode=$?
          [ $returnCode -eq 0 ] || return ${ERR_GETPRODTYPE}
          prodTypeName=$(sed -n -e 's|^.*<ProductLevel>\(.*\)</ProductLevel>$|\1|p' *MSS2.xml)
          rm -f *MSS2.xml
      else
	  ciop-log "ERROR" "Failed to get product type from : ${retrievedProduct}"
	  ciop-log "ERROR" "Product extension not equal to the expected"
          return $ERR_WRONGPRODTYPE
      fi
      [[ "$prodTypeName" != "LEVEL2A" ]] && return $ERR_WRONGPRODTYPE
  fi
  
  if [[ "${mission}" == "RapidEye" ]]; then
      # prodcut name assumed like TTTTTTT_DDDD-DD-DD_RE?_LL_HHHHHH
      # where LL is the product level
      prodTypeName=${productName:23:2}
      [[ "$prodTypeName" != "3A" ]] && return $ERR_WRONGPRODTYPE
  fi

  if [[ "${mission}" == "VRSS1" ]]; then
      filename="${retrievedProduct##*/}"; ext="${filename#*.}"
      # assumption is that the product has .tar extension or is already uncompressed
      if  [[ "$ext" == "tar" ]]; then
      # if tar uncompress the product 
          ciop-log "INFO" "Running command: tar xf $retrievedProduct"
          tar xf $retrievedProduct 
          returnCode=$?
          [ $returnCode -eq 0 ] || return ${ERR_GETPRODTYPE}
          # find the fisrt band tif product 
          vrss1_b1=$(find ./ -name '*_1.tif')
          [[ "${vrss1_b1}" == "" ]] && return ${ERR_GETPRODTYPE}
          dir_untar_vrss1=$(dirname ${vrss1_b1})
          rm -r -f ${dir_untar_vrss1} 
      else
          vrss1_b1=$(find ${retrievedProduct}/ -name '*_1.tif')
          [[ "${vrss1_b1}" == "" ]] && return ${ERR_GETPRODTYPE}
      fi
      # extract product type from product name
      vrss1_b1=$(basename ${vrss1_b1})
      l2b_test=$(echo "${vrss1_b1}" | grep "L2B")
      [[ "${l2b_test}" != "" ]] && prodTypeName="L2B" ||  return $ERR_WRONGPRODTYPE
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
	prod_basename_substr_8=${prod_basename:0:8}
        prod_basename_substr_10=${prod_basename:0:10}

	[ "${prod_basename_substr_3}" = "S1A" ] && mission="Sentinel-1"
        [ "${prod_basename_substr_3}" = "S1B" ] && mission="Sentinel-1"
        [ "${prod_basename_substr_3}" = "S2A" ] && mission="Sentinel-2"
        [ "${prod_basename_substr_3}" = "S2B" ] && mission="Sentinel-2"
        [ "${prod_basename_substr_3}" = "S3A" ] && mission="Sentinel-3"
        [ "${prod_basename_substr_3}" = "S3B" ] && mission="Sentinel-3"
        [ "${prod_basename_substr_3}" = "K5_" ] && mission="Kompsat-5"
        [ "${prod_basename_substr_3}" = "K3_" ] && mission="Kompsat-3"
	[ "${prod_basename_substr_3}" = "LC8" ] && mission="Landsat-8"
        [ "${prod_basename_substr_4}" = "LC08" ] && mission="Landsat-8"
        [ "${prod_basename_substr_4}" = "LS08" ] && mission="Landsat-8"
        [ "${prod_basename_substr_4}" = "MSC_" ] && mission="Kompsat-2"
        [ "${prod_basename_substr_4}" = "FCGC" ] && mission="Pleiades"
	[ "${prod_basename_substr_5}" = "CHART" ] && mission="Pleiades"
        [ "${prod_basename_substr_5}" = "U2007" ] && mission="UK-DMC2"
	[ "${prod_basename_substr_5}" = "ORTHO" ] && mission="UK-DMC2"
        [ "${prod_basename_substr_10}" = "SENTINEL_2" ] && mission="Sentinel-2"

        ukdmc2_test=$(echo "${prod_basename}" | grep "UK-DMC-2")
        [ "${ukdmc2_test}" = "" ] || mission="UK-DMC-2"
        if [[ "${prod_basename_substr_8}" == "RESURS_P" ]] || [[ "${prod_basename_substr_8}" == "RESURS-P" ]] || [[ "${prod_basename_substr_8}" == "Resurs-P" ]] || [[ "${prod_basename_substr_8}" == "Resurs_P" ]] ; then
            mission="Resurs-P"
        fi
        if [[ "${prod_basename_substr_9}" == "KANOPUS_V" ]] || [[ "${prod_basename_substr_9}" == "KANOPUS-V" ]] || [[ "${prod_basename_substr_9}" == "Kanopus-V" ]] || [[ "${prod_basename_substr_9}" == "Kanopus_V" ]] ; then 
            mission="Kanopus-V"
        fi
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
        [ "${prod_basename_substr_4}" = "RS2_" ] && mission="Radarsat-2"
	[ "${prod_basename_substr_3}" = "GF2" ] && mission="GF2"
        rapideye_test=${prod_basename:19:2}
        [ "${rapideye_test}" = "RE" ] && mission="RapidEye"
        vrss1_test_1=$(echo "${prod_basename}" | grep "VRSS1")
        vrss1_test_2=$(echo "${prod_basename}" | grep "VRSS-1")
        if [[ "${vrss1_test_1}" != "" ]] || [[ "${vrss1_test_2}" != "" ]]; then
	    mission="VRSS1"
	fi

  	if [ "${mission}" != "" ] ; then
     	    echo ${mission}
  	else
     	    return ${ERR_GETMISSION}
  	fi
}


function get_polarization_s1() {

  local productName=$1

  #productName assumed like S1A_IW_SLC__1SPP_* where PP is the polarization to be extracted

  polarizationName=$( echo ${productName:14:2} )
  [ -z "${polarizationName}" ] && return ${ERR_GETPOLARIZATION}

  #check on extracted polarization
  # allowed values are: SH SV DH DV
  if [ "${polarizationName}" = "DH" ] || [ "${polarizationName}" = "DV" ] || [ "${polarizationName}" = "SH" ] || [ "${polarizationName}" = "SV" ]; then
     echo ${polarizationName}
     return 0
  else
     return ${ERR_WRONGPOLARIZATION}
  fi
}

# function that gets the Sentinel-1 acquisition mode from product name
function get_s1_acq_mode(){
# function call get_s1_acq_mode "${prodname}"
local prodname=$1
# filename convention assumed like S1A_AA_* where AA is the acquisition mode to be extracted
acqMode=$( echo ${prodname:4:2} )
echo ${acqMode}
return 0
}

function create_cloudcover_geotiff_S3() {
# function call create_cloudcover_geotiff_S3 "${retrieved_xml}" "${outProd}"

# function which creates the actual request from
# a template and returns the path to the request

#inputNum=$#
#[ "$inputNum" -ne 2 ] && return ${SNAP_REQUEST_ERROR}

local retrieved_xml=$1
local outProd=$2
#sets the output filename
snap_request_filename="${TMPDIR}/$( uuidgen ).xml"

   cat << EOF > ${snap_request_filename}
<graph id="Graph">
  <version>1.0</version>
  <node id="Read">
    <operator>Read</operator>
    <sources/>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <file>${retrieved_xml}</file>
    </parameters>
  </node>
  <node id="Reproject">
    <operator>Reproject</operator>
    <sources>
      <sourceProduct refid="Read"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <wktFile/>
      <crs>PROJCS[&quot;WGS 84 / Pseudo-Mercator&quot;, &#xd;
  GEOGCS[&quot;WGS 84&quot;, &#xd;
    DATUM[&quot;World Geodetic System 1984&quot;, &#xd;
      SPHEROID[&quot;WGS 84&quot;, 6378137.0, 298.257223563, AUTHORITY[&quot;EPSG&quot;,&quot;7030&quot;]], &#xd;
      AUTHORITY[&quot;EPSG&quot;,&quot;6326&quot;]], &#xd;
    PRIMEM[&quot;Greenwich&quot;, 0.0, AUTHORITY[&quot;EPSG&quot;,&quot;8901&quot;]], &#xd;
    UNIT[&quot;degree&quot;, 0.017453292519943295], &#xd;
    AXIS[&quot;Geodetic longitude&quot;, EAST], &#xd;
    AXIS[&quot;Geodetic latitude&quot;, NORTH], &#xd;
    AUTHORITY[&quot;EPSG&quot;,&quot;4326&quot;]], &#xd;
  PROJECTION[&quot;Popular Visualisation Pseudo Mercator&quot;, AUTHORITY[&quot;EPSG&quot;,&quot;1024&quot;]], &#xd;
  PARAMETER[&quot;semi_minor&quot;, 6378137.0], &#xd;
  PARAMETER[&quot;latitude_of_origin&quot;, 0.0], &#xd;
  PARAMETER[&quot;central_meridian&quot;, 0.0], &#xd;
  PARAMETER[&quot;scale_factor&quot;, 1.0], &#xd;
  PARAMETER[&quot;false_easting&quot;, 0.0], &#xd;
  PARAMETER[&quot;false_northing&quot;, 0.0], &#xd;
  UNIT[&quot;m&quot;, 1.0], &#xd;
  AXIS[&quot;Easting&quot;, EAST], &#xd;
  AXIS[&quot;Northing&quot;, NORTH], &#xd;
  AUTHORITY[&quot;EPSG&quot;,&quot;3857&quot;]]</crs>
      <resampling>Nearest</resampling>
      <referencePixelX/>
      <referencePixelY/>
      <easting/>
      <northing/>
      <orientation/>
      <pixelSizeX/>
      <pixelSizeY/>
      <width/>
      <height/>
      <tileSizeX/>
      <tileSizeY/>
      <orthorectify>false</orthorectify>
      <elevationModelName/>
      <noDataValue>NaN</noDataValue>
      <includeTiePointGrids>true</includeTiePointGrids>
      <addDeltaBands>false</addDeltaBands>
    </parameters>
  </node>
  <node id="BandMaths">
    <operator>BandMaths</operator>
    <sources>
      <sourceProduct refid="Reproject"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <targetBands>
        <targetBand>
          <name>cloudmask</name>
          <type>float32</type>
          <expression>quality_flags_bright</expression>
          <description/>
          <unit/>
          <noDataValue>0.0</noDataValue>
        </targetBand>
      </targetBands>
      <variables/>
    </parameters>
  </node>
  <node id="Write">
    <operator>Write</operator>
    <sources>
      <sourceProduct refid="BandMaths"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <file>${outProd}</file>
      <formatName>GeoTIFF</formatName>
    </parameters>
  </node>
  <applicationData id="Presentation">
    <Description/>
    <node id="Read">
            <displayPosition x="37.0" y="134.0"/>
    </node>
    <node id="Reproject">
      <displayPosition x="151.0" y="135.0"/>
    </node>
    <node id="BandMaths">
      <displayPosition x="271.0" y="137.0"/>
    </node>
    <node id="Write">
            <displayPosition x="512.0" y="144.0"/>
    </node>
  </applicationData>
</graph>
EOF

    [ $? -eq 0 ] && {
        echo "${snap_request_filename}"
        return 0
    } || return ${SNAP_REQUEST_ERROR}
}

function create_snap_request_cal_ml_tc_db_scale_byte() {

# function call create_snap_request_cal_ml_tc_db_scale_byte "${s1_manifest}" "${bandCoPol}" "${ml_factor}" "${pixelsize}" "${outProd}"

# function which creates the actual request from
# a template and returns the path to the request

inputNum=$#
[ "$inputNum" -ne 5 ] && return ${SNAP_REQUEST_ERROR}

local s1_manifest=$1
local bandCoPol=$2
local ml_factor=$3
local pixelsize=$4
local outProd=$5

local commentMlBegin=""
local commentMlEnd=""
local commentCalSrcBegin=""
local commentCalSrcEnd=""

local beginCommentXML="<!--"
local endCommentXML="-->"
# skip multilook operation if ml_factor=1
if [ "$ml_factor" -eq 1 ] ; then
    commentMlBegin="${beginCommentXML}"
    commentMlEnd="${endCommentXML}"
else
    commentCalSrcBegin="${beginCommentXML}"
    commentCalSrcEnd="${endCommentXML}"
fi
#compute pixel spacing according to the multilook factor
pixelSpacing=$(echo "scale=1; $pixelsize*$ml_factor" | bc )
#sets the output filename
snap_request_filename="${TMPDIR}/$( uuidgen ).xml"

   cat << EOF > ${snap_request_filename}
<graph id="Graph">
  <version>1.0</version>
  <node id="Read">
    <operator>Read</operator>
    <sources/>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <file>${s1_manifest}</file>
    </parameters>
  </node>
  <node id="Remove-GRD-Border-Noise">
    <operator>Remove-GRD-Border-Noise</operator>
    <sources>
      <sourceProduct refid="Read"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <selectedPolarisations/>
      <borderLimit>1000</borderLimit>
      <trimThreshold>0.5</trimThreshold>
    </parameters>
  </node>
  <node id="Calibration">
    <operator>Calibration</operator>
    <sources>
      <sourceProduct refid="Remove-GRD-Border-Noise"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <sourceBands/>
      <auxFile>Product Auxiliary File</auxFile>
      <externalAuxFile/>
      <outputImageInComplex>false</outputImageInComplex>
      <outputImageScaleInDb>false</outputImageScaleInDb>
      <createGammaBand>false</createGammaBand>
      <createBetaBand>false</createBetaBand>
      <selectedPolarisations/>
      <outputSigmaBand>true</outputSigmaBand>
      <outputGammaBand>false</outputGammaBand>
      <outputBetaBand>false</outputBetaBand>
    </parameters>
  </node>
${commentMlBegin}  <node id="Multilook">
    <operator>Multilook</operator>
    <sources>
      <sourceProduct refid="Calibration"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <sourceBands/>
      <nRgLooks>${ml_factor}</nRgLooks>
      <nAzLooks>${ml_factor}</nAzLooks>
      <outputIntensity>true</outputIntensity>
      <grSquarePixel>true</grSquarePixel>
    </parameters>
  </node> ${commentMlEnd}
  <node id="Terrain-Correction">
    <operator>Terrain-Correction</operator>
    <sources>
${commentMlBegin}       <sourceProduct refid="Multilook"/> ${commentMlEnd}
${commentCalSrcBegin}   <sourceProduct refid="Calibration"/>  ${commentCalSrcEnd}
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <sourceBands/>
      <demName>SRTM 3Sec</demName>
      <externalDEMFile/>
      <externalDEMNoDataValue>0.0</externalDEMNoDataValue>
      <externalDEMApplyEGM>true</externalDEMApplyEGM>
      <demResamplingMethod>BILINEAR_INTERPOLATION</demResamplingMethod>
      <imgResamplingMethod>BILINEAR_INTERPOLATION</imgResamplingMethod>
      <pixelSpacingInMeter>${pixelSpacing}</pixelSpacingInMeter>
      <!-- <pixelSpacingInDegree>1.796630568239043E-4</pixelSpacingInDegree> -->
      <mapProjection>WGS84(DD)</mapProjection>
      <nodataValueAtSea>false</nodataValueAtSea>
      <saveDEM>false</saveDEM>
      <saveLatLon>false</saveLatLon>
      <saveIncidenceAngleFromEllipsoid>false</saveIncidenceAngleFromEllipsoid>
      <saveLocalIncidenceAngle>false</saveLocalIncidenceAngle>
      <saveProjectedLocalIncidenceAngle>false</saveProjectedLocalIncidenceAngle>
      <saveSelectedSourceBand>true</saveSelectedSourceBand>
      <outputComplex>false</outputComplex>
      <applyRadiometricNormalization>false</applyRadiometricNormalization>
      <saveSigmaNought>false</saveSigmaNought>
      <saveGammaNought>false</saveGammaNought>
      <saveBetaNought>false</saveBetaNought>
      <incidenceAngleForSigma0>Use projected local incidence angle from DEM</incidenceAngleForSigma0>
      <incidenceAngleForGamma0>Use projected local incidence angle from DEM</incidenceAngleForGamma0>
      <auxFile>Latest Auxiliary File</auxFile>
      <externalAuxFile/>
    </parameters>
  </node>
  <node id="LinearToFromdB">
    <operator>LinearToFromdB</operator>
    <sources>
      <sourceProduct refid="Terrain-Correction"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <sourceBands/>
    </parameters>
  </node>
  <node id="BandSelect">
    <operator>BandSelect</operator>
    <sources>
      <sourceProduct refid="LinearToFromdB"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <selectedPolarisations/>
      <sourceBands>${bandCoPol}</sourceBands>
      <bandNamePattern/>
    </parameters>
  </node>
  <node id="BandMaths">
    <operator>BandMaths</operator>
    <sources>
      <sourceProduct refid="BandSelect"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <targetBands>
        <targetBand>
          <name>clipped</name>
          <type>float32</type>
          <expression>if fneq(${bandCoPol},0.0) then (if ${bandCoPol}&lt;=-15 then -15 else (if ${bandCoPol}&gt;=5 then 5 else ${bandCoPol})) else NaN</expression>
          <description/>
          <unit/>
          <noDataValue>NaN</noDataValue>
        </targetBand>
      </targetBands>
      <variables/>
    </parameters>
  </node>
  <node id="BandMaths(2)">
    <operator>BandMaths</operator>
    <sources>
      <sourceProduct refid="BandMaths"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <targetBands>
        <targetBand>
          <name>quantized</name>
          <type>uint8</type>
          <expression>if !nan(clipped) then floor(clipped*12.7+191.5) else NaN</expression>
          <description/>
          <unit/>
          <noDataValue>NaN</noDataValue>
        </targetBand>
      </targetBands>
      <variables/>
    </parameters>
  </node>
  <node id="Write">
    <operator>Write</operator>
    <sources>
      <sourceProduct refid="BandMaths(2)"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <file>${outProd}</file>
      <formatName>GeoTIFF-BigTIFF</formatName>
    </parameters>
  </node>
  <applicationData id="Presentation">
    <Description/>
    <node id="Read">
            <displayPosition x="37.0" y="134.0"/>
    </node>
    <node id="Calibration">
      <displayPosition x="117.0" y="134.0"/>
    </node>
    <node id="Terrain-Correction">
      <displayPosition x="208.0" y="133.0"/>
    </node>
    <node id="LinearToFromdB">
      <displayPosition x="345.0" y="135.0"/>
    </node>
    <node id="BandSelect">
      <displayPosition x="472.0" y="131.0"/>
    </node>
    <node id="Write">
            <displayPosition x="578.0" y="133.0"/>
    </node>
  </applicationData>
</graph>
EOF

    [ $? -eq 0 ] && {
        echo "${snap_request_filename}"
        return 0
    } || return ${SNAP_REQUEST_ERROR}
}


# function that generate the full res geotiff image from the original data product
function generate_full_res_tif (){
# function call generate_full_res_tif "${retrievedProduct}" "${mission}
  
  local retrievedProduct=$1
  local productName=$( basename "$retrievedProduct" )
  local prodNameNoExt="${productName%%.*}"
  local mission=$2
  
  if [ ${mission} = "Sentinel-1"  ] ; then

    if [[ -d "${retrievedProduct}" ]]; then
      s1_manifest=$(find ${retrievedProduct}/ -name 'manifest.safe')
      ciop-log "DEBUG" "s1_manifest ${s1_manifest}"
      polType=$( get_polarization_s1 "${productName}" )
      [[ $? -eq 0  ]] || return $?
      # rasterization of on co-polarized channel
      case "$polType" in
          "SH")
              bandCoPol="Sigma0_HH_db"
              ;;
          "SV")
              bandCoPol="Sigma0_VV_db"
              ;;
          "DH")
              bandCoPol="Sigma0_HH_db"
              ;;
          "DV")
              bandCoPol="Sigma0_VV_db"
              ;;
      esac
      # get product type
      s1_prod_type=$( check_product_type "${retrievedProduct}" "${mission}" )
      s1_acq_mode=$(get_s1_acq_mode "${productName}")
      # default multilook factor = 2
      ml_factor=2
      # default pixel spacing = 20m
      pixelsize=10
      if [ "${s1_acq_mode}" == "EW" ]; then
          if [ "${s1_prod_type}" == "GRDH" ]; then
              pixelsize=25
              ml_factor=1
          elif [ "${s1_prod_type}" == "GRDM" ]; then
              pixelsize=40
              ml_factor=1
          fi
      elif [ "${s1_acq_mode}" == "IW" ]; then
          if [ "${s1_prod_type}" == "GRDH" ]; then
              pixelsize=10
              ml_factor=2
          elif [ "${s1_prod_type}" == "GRDM" ]; then
              pixelsize=40
              ml_factor=1
          fi
      fi
      outProd=${TMPDIR}/s1_cal_tc_db_co_pol
      outProdTIF=${outProd}.tif
      # prepare the SNAP request
      SNAP_REQUEST=$( create_snap_request_cal_ml_tc_db_scale_byte "${s1_manifest}" "${bandCoPol}" "${ml_factor}" "${pixelsize}" "${outProd}")
      [ $? -eq 0 ] || return ${SNAP_REQUEST_ERROR}
      [ $DEBUG -eq 1 ] && cat ${SNAP_REQUEST}
      # report activity in the log
      ciop-log "INFO" "Generated request file: ${SNAP_REQUEST}"
      # report activity in the log
      ciop-log "INFO" "Invoking SNAP-gpt on the generated request file for Sentinel 1 data pre processing"
      # invoke the ESA SNAP toolbox
      gpt $SNAP_REQUEST -c "${CACHE_SIZE}" &> /dev/null
      # check the exit code
      [ $? -eq 0 ] || return $ERR_SNAP
      # report activity in the log
      ciop-log "INFO" "Invoking gdalwarp for tif reprojection and alpha band creation"
      # gdalwarp for tif reprojection and alpha band creation
      gdalwarp -ot Byte -t_srs EPSG:3857 -srcnodata 0 -dstnodata 0 -dstalpha -co "ALPHA=YES" ${outProdTIF} ${OUTPUTDIR}/${prodNameNoExt}_${bandCoPol}.tif       
      returnCode=$?
      [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
      gdaladdo -r average ${OUTPUTDIR}/${prodNameNoExt}_${bandCoPol}.tif 2 4 8 16
      # cleanup
      rm -f ${outProdTIF}

    else
      ciop-log "ERROR" "The retrieved product ${retrievedProduct} is not a directory or does not exist"
      return ${ERR_UNPACKING}
    fi

  fi

  if [ ${mission} = "Sentinel-2"  ] ; then
      # output product name
      outputProd=$(basename ${retrievedProduct}) 
      # try to get path of True Color Image file
      tci=$(find ${retrievedProduct}/ -name '*.jp2' | egrep '*_TCI.jp2$')
      #if not found then go to backup solution: make image using R=B4 G=B3 B=B2 
      if [ $? -ne 0 ] ; then
          #get full path of S2 product metadata xml file
          # check if it is like S2?_*.xml
          s2_xml=$(find ${retrievedProduct}/ -name '*.xml' | egrep '^.*/S2[A-Z]?_.*.SAFE/S2[A-Z]?_[A-Z0-9]*.xml$') 
          # if it not like S2?_*.xml
          if [ $? -ne 0 ] ; then
              # check if it is like MTD_*.xml
              s2_xml=$(find ${retrievedProduct}/ -name '*.xml' | egrep '^.*/S2[A-Z]?_.*.SAFE/MTD_[A-Z0-9]*.xml$')
              #if it is neither like MTD_*.xml: return error
              [ $? -ne 0 ] && return $ERR_GETPRODMTD
          fi
          # create full resolution tif image with Red=B4 Green=B3 Blue=B2
          pconvert -b 4,3,2 -f tif -o ${OUTPUTDIR} ${s2_xml} &> /dev/null
          # check the exit code
          [ $? -eq 0 ] || return $ERR_PCONVERT
          # get pconvert output file 
          outputfile=$(ls ${OUTPUTDIR} | egrep '^.*.tif$')
          # since pconvert out is not the final product to be published, rename and move it to temp folder
          tmp_outputfile="tmp_${outputfile}"
      	  mv ${OUTPUTDIR}/$outputfile ${OUTPUTDIR}/$tmp_outputfile
          # re-projection
          gdalwarp -ot Byte -t_srs EPSG:3857 -srcalpha -dstalpha -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" ${OUTPUTDIR}/$tmp_outputfile ${OUTPUTDIR}/$outputfile
          returnCode=$?
          [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
          #Remove temporary file
          rm -f ${OUTPUTDIR}/$tmp_outputfile
          rm -f ${OUTPUTDIR}/*.xml
          #Add overviews
          gdaladdo -r average ${OUTPUTDIR}/$outputfile 2 4 8 16
          returnCode=$?
          [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
      else
          # translate the jp2 file in GeoTIFF
          gdal_translate -ot Byte -of GTiff -b 1 -b 2 -b 3 -scale -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" ${tci} temp-outputfile.tif
          #re-projection
          gdalwarp -ot Byte -t_srs EPSG:3857 -srcnodata 0 -dstnodata 0 -dstalpha -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" temp-outputfile.tif ${OUTPUTDIR}/${outputProd}.tif
          returnCode=$?
          [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
          #Remove temporary file
          rm -f temp-outputfile.tif
          #Add overviews
          gdaladdo -r average ${OUTPUTDIR}/${outputProd}.tif 2 4 8 16
          returnCode=$?
          [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
      fi             

  fi

  if [ ${mission} = "Sentinel-3" ]; then
	ciop-log "INFO" "Making full resolution tif for ${mission}"
	#retrieve XML file for Sentinel 3 image
			## Create RGB composite Sentinel 3
		retrieved_xml=$(find ${retrievedProduct}/ -name '*.xml' )
		ciop-log "INFO" "The retrieved xml file is: ${retrieved_xml}"
		target=${TMPDIR}/${productName}.tif
		ciop-log "INFO" "The target dim file is: ${target}"
		
		SNAP_REQUEST=$( create_snap_request_rad2refl_reproj_s3 "${target}" "${retrieved_xml}" )
		[ $? -eq 0 ] || return ${SNAP_REQUEST_ERROR}
	        [ $DEBUG -eq 1 ] && cat ${SNAP_REQUEST}
        	  # report activity in the log
         	ciop-log "INFO" "Generated request file: ${SNAP_REQUEST}"
        	  # report activity in the log
         	ciop-log "INFO" "Invoking SNAP-gpt on the generated request file for radiance to reflectance calculation and reprojection"
          	# invoke the ESA SNAP toolbox
          	gpt $SNAP_REQUEST -c "${CACHE_SIZE}" &> /dev/null
          	# check the exit code
          	[ $? -eq 0 ] || return $ERR_SNAP
		# edit on the fly the RGB image profile file that will be applied by pconvert
		cat << EOF > ${TMPDIR}/Sentinel3_fullres.rgb
#RGB-Image Profile
#Fri Mar 23 16:46:55 CET 2018
name=Sentinel3_fullres
blue=log(0.05 + 0.07 * Oa01_reflectance + 0.28 * Oa02_reflectance + 1.77 * Oa03_reflectance + 0.47 * Oa04_reflectance + 0.16 * Oa05_reflectance)
green=log(0.05 + 0.26 * Oa03_reflectance + 0.21 * Oa04_reflectance + 0.50 * Oa05_reflectance + Oa06_reflectance + 0.38 * Oa07_reflectance + 0.04 * Oa08_reflectance + 0.03 * Oa09_reflectance + 0.02 * Oa10_reflectance)
red=log(0.05 + 0.01 * Oa01_reflectance + 0.09 * Oa02_reflectance + 0.35 * Oa03_reflectance + 0.04 * Oa04_reflectance + 0.01 * Oa05_reflectance + 0.59 * Oa06_reflectance + 0.85 * Oa07_reflectance + 0.12 * Oa08_reflectance + 0.07 * Oa09_reflectance + 0.04 * Oa10_reflectance)
EOF
		# Full Resolution product 8 bit encoded 
		pconvert -f tif -p ${TMPDIR}/Sentinel3_fullres.rgb -s 0,0 -o ${TMPDIR} ${target} &> /dev/null
		# check the exit 
		[ $? -eq 0 ] || return $ERR_PCONVERT
		# output of pconvert
		pconvertOutRgbCompositeTIF=${TMPDIR}/${productName}.tif
		#Final product name
	 	rgbCompositeNameFullResTIF=${OUTPUTDIR}/${productName}.rgb.tif
		# remove corrupted alpha band through gdal_translate
		gdal_translate -ot Byte -of GTiff -b 1 -b 2 -b 3 -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "PHOTOMETRIC=RGB" ${pconvertOutRgbCompositeTIF} temp-outputfile.tif
		returnCode=$?
		[ $returnCode -eq 0 ] || return ${ERR_CONVERT}
	       	# reprojection
		gdalwarp -ot Byte -t_srs EPSG:3857 -srcnodata 0 -dstnodata 0 -dstalpha -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" temp-outputfile.tif ${rgbCompositeNameFullResTIF}
		returnCode=$?
		[ $returnCode -eq 0 ] || return ${ERR_CONVERT}
		# Add overviews
		gdaladdo -r average ${rgbCompositeNameFullResTIF} 2 4 8 16
		#output of snap request file for cloudcover geotiff
		productName_cloudcover=${productName}_cloudcover
		cloudcoverProduct=${TMPDIR}/${productName_cloudcover}.tif
                #Final product name
                CloudcoverFinalProduct=${OUTPUTDIR}/${productName_cloudcover}.rgb.tif
		ciop-log "INFO" "Creating snap request file for cloud geotiff with ${retrieved_xml} and ${cloudcoverProduct}"
		#creation of snap request file for cloudcover geotiff
                SNAP_REQUEST_cloudcover=$( create_cloudcover_geotiff_S3 "${retrieved_xml}" "${cloudcoverProduct}" )
		#[$? -eq 0 ] || return ${SNAP_REQUEST_ERROR}
                [ $DEBUG -eq 1 ] && cat ${SNAP_REQUEST_cloudcover}
                # report activity in the log
                ciop-log "INFO" "Generated request file: ${SNAP_REQUEST_cloudcover}"
                  # report activity in the log
                ciop-log "INFO" "Invoking SNAP-gpt on the generated request file for producing a cloudcover geotiff"
                # invoke the ESA SNAP toolbox
                gpt $SNAP_REQUEST_cloudcover -c "${CACHE_SIZE}" &> /dev/null
                # check the exit code
                [ $? -eq 0 ] || return $ERR_SNAP
 		
		
		
		gdal_translate -ot Byte -of GTiff -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "PHOTOMETRIC=MINISBLACK" ${cloudcoverProduct} ${CloudcoverFinalProduct}
                #gdalwarp -ot Byte -t_srs EPSG:3857 -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "PHOTOMETRIC=MINISBLACK" temp-outputfile2.tif ${CloudcoverFinalProduct}
		gdaladdo -r average ${CloudcoverFinalProduct} 2 4 8 16
		returnCode=$?
		[ $returnCode -eq 0 ] || return ${ERR_CONVERT}
		rm ${pconvertOutRgbCompositeTIF} ${target} temp-outputfile.tif temp-outputfile2.tif
  fi

  if [ ${mission} = "Landsat-8" ]; then
      #Check if downloaded product is compressed and extract it
      ext="${retrievedProduct##*/}"; ext="${ext#*.}"
      ciop-log "INFO" "Product extension is: $ext"
      if [[ "$ext" == "tar.bz" ]]; then
          ciop-log "INFO" "Extracting $retrievedProduct"
          currentBasename=$(basename $retrievedProduct)
          currentBasename="${currentBasename%%.*}"
	  mkdir -p ${retrievedProduct%/*}/${currentBasename}
          cd ${retrievedProduct%/*}
          filename="${retrievedProduct##*/}" 
	  tar xjf $filename -C ${currentBasename}
          returnCode=$?
          [ $returnCode -eq 0 ] || return ${ERR_UNPACKING}
	  #Define output filename
          prodname=${retrievedProduct%/*}/${currentBasename}
          #Get RGB band filenames
	  RED=$(ls "${prodname}"/LC8*_B4.TIF)
	  GREEN=$(ls "${prodname}"/LC8*_B3.TIF)
	  BLUE=$(ls "${prodname}"/LC8*_B2.TIF)
       elif [[ "$ext" == "tar" ]]; then
          ciop-log "INFO" "Extracting $retrievedProduct"
          currentBasename=$(basename $retrievedProduct)
          currentBasename="${currentBasename%%.*}"
          mkdir -p ${retrievedProduct%/*}/${currentBasename}
          cd ${retrievedProduct%/*}
          filename="${retrievedProduct##*/}"
          tar xf $filename -C ${currentBasename}
          returnCode=$?
          [ $returnCode -eq 0 ] || return ${ERR_UNPACKING}
          prodname=${retrievedProduct%/*}/${currentBasename}
          # in these particular case the product name is not common
          # to the base band names ---> rename all bands
          prodBasename=$(basename ${prodname})
          for bix in 2 3 4;
          do
             currentTif=$(ls "${prodname}"/LC08*_B"${bix}".TIF)
             mv ${currentTif} ${prodname}/${prodBasename}_B${bix}.TIF
	  done
          RED=$(ls "${prodname}"/${prodBasename}_B4.TIF) 
          GREEN=$(ls "${prodname}"/${prodBasename}_B3.TIF)
          BLUE=$(ls "${prodname}"/${prodBasename}_B2.TIF)
      else
          prodname=${retrievedProduct}
          RED=$(ls "${prodname}"/LS08*_B04.TIF) 
          GREEN=$(ls "${prodname}"/LS08*_B03.TIF) 
          BLUE=$(ls "${prodname}"/LS08*_B02.TIF)
      fi
      ciop-log "INFO" "Generate RGB TIF from LANDSAT-8 TIF bands"
      #define output filename
      outputfile=$(basename ${prodname})
      outputfile=${outputfile}.tif
      # histogram skip (percentiles from 2 to 95) on separated bands
      python $_CIOP_APPLICATION_PATH/data_download_publish/hist_skip_no_zero.py "${RED}" 1 2 85 "temp-outputfile_band_r.tif"
      python $_CIOP_APPLICATION_PATH/data_download_publish/hist_skip_no_zero.py "${GREEN}" 1 2 85 "temp-outputfile_band_g.tif"
      python $_CIOP_APPLICATION_PATH/data_download_publish/hist_skip_no_zero.py "${BLUE}" 1 2 85 "temp-outputfile_band_b.tif"
      gdal_merge.py -separate -n 0 -a_nodata 0 -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" "temp-outputfile_band_r.tif" "temp-outputfile_band_g.tif" "temp-outputfile_band_b.tif" -o ${TMPDIR}/temp-outputfile.tif
      #remove temp files
      rm temp-outputfile_band_r.tif temp-outputfile_band_g.tif temp-outputfile_band_b.tif
      # re-projection
      gdalwarp -ot Byte -t_srs EPSG:3857 -srcnodata 0 -dstnodata 0 -dstalpha -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" ${TMPDIR}/temp-outputfile.tif ${outputfile}
      returnCode=$?
      [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
      #Add overviews
      gdaladdo -r average ${outputfile} 2 4 8 16
      returnCode=$?
      [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
      # remove temp files
      rm ${TMPDIR}/temp-outputfile.tif
      # move result to output folder
      mv ${outputfile} ${OUTPUTDIR}/

  fi
  

  if [ ${mission} = "Kompsat-2" ] || [ ${mission} = "Kompsat-3" ] ; then
      if [[ -d "${retrievedProduct}" ]]; then
          local RED=""
	  local GREEN=""
	  local BLUE=""
          cd ${retrievedProduct}
	  # Select RGB bands dependiong on mission 
          if [ ${mission} = "Kompsat-2" ]; then
              RED=$(find ${retrievedProduct} -name '*.tif' | egrep '.*MSC_.*R_[0-9A-Zaz]{2}.tif$')
	      GREEN=$(find ${retrievedProduct} -name '*.tif' | egrep '.*MSC_.*G_[0-9A-Zaz]{2}.tif$')
	      BLUE=$(find ${retrievedProduct} -name '*.tif' | egrep '.*MSC_.*B_[0-9A-Zaz]{2}.tif$')
	  elif [ ${mission} = "Kompsat-3" ]; then
              RED=$(find ${retrievedProduct}/ -name 'K3_*_R.tif')
              GREEN=$(find ${retrievedProduct}/ -name 'K3_*_G.tif')
              BLUE=$(find ${retrievedProduct}/ -name  'K3_*_B.tif')
          else
	      return ${ERR_GETDATA}
	  fi
	  #defin output filename
	  outputfile=${productName}.tif
          ciop-log "INFO" "Generate RGB TIF from Kompsat TIF bands"
          # histogram skip (percentiles from 2 to 95) on separated bands
          python $_CIOP_APPLICATION_PATH/data_download_publish/hist_skip_no_zero.py "${RED}" 1 2 96 "temp-outputfile_band_r.tif"
          python $_CIOP_APPLICATION_PATH/data_download_publish/hist_skip_no_zero.py "${GREEN}" 1 2 96 "temp-outputfile_band_g.tif"
          python $_CIOP_APPLICATION_PATH/data_download_publish/hist_skip_no_zero.py "${BLUE}" 1 2 96 "temp-outputfile_band_b.tif"
          gdal_merge.py -separate -n 0 -a_nodata 0 -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" "temp-outputfile_band_r.tif" "temp-outputfile_band_g.tif" "temp-outputfile_band_b.tif" -o ${TMPDIR}/temp-outputfile.tif
          rm temp-outputfile_band_r.tif temp-outputfile_band_g.tif temp-outputfile_band_b.tif
          cd - 2>/dev/null
          # re-projection
          gdalwarp -ot Byte -t_srs EPSG:3857 -srcnodata 0 -dstnodata 0 -dstalpha -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" ${TMPDIR}/temp-outputfile.tif ${outputfile}
          returnCode=$?
          [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
          #Add overviews
          gdaladdo -r average ${outputfile} 2 4 8 16
          returnCode=$?
          [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
          # remove temp files
          rm ${TMPDIR}/temp-outputfile.tif
          # move result to output folder
          mv ${outputfile} ${OUTPUTDIR}/
      else
          ciop-log "ERROR" "The retrieved KOMPSAT-3 product is not a directory"
          return ${ERR_GETDATA}
      fi
  fi

  if [ ${mission} = "Pleiades" ] || [ ${mission} = "SPOT-6" ] || [ ${mission} = "SPOT-7" ]; then
      if [[ -d "${retrievedProduct}" ]]; then
          #move into current product folder
	  cd ${retrievedProduct}
          jp2_product=""
          # Get multispectral image file
          if [ ${mission} = "Pleiades" ]; then
              jp2_product=$(find ${retrievedProduct}/ -name 'IMG_*MS_*.JP2')
          else
              # SPOT case
              jp2_product=$(find ${retrievedProduct}/ -name 'IMG_SPOT?_*MS_*.JP2')
          fi 
          # convert ssv to array
          declare -a jp2_product_arr=(${jp2_product})
          # get number of bands
          local numProd=${#jp2_product_arr[@]}
          [ $numProd -eq 0  ] && return ${ERR_CONVERT}
          local prodId=0
          let "numProd-=1"
          for prodId in `seq 0 $numProd`; do
              currentProd=${jp2_product_arr[$prodId]}
	      #set output filename
	      outputfile="${currentProd##*/}"; outputfile="${outputfile%.JP2}.tif"
              #run OTB optical calibration
              otbcli_OpticalCalibration -in ${currentProd} -out temp-outputfile.tif -ram ${RAM_AVAILABLE}
              returnCode=$?
              [ $returnCode -eq 0 ] || return ${ERR_OTB}
              # histogram skip (percentiles from 2 to 95) on separated bands
              python $_CIOP_APPLICATION_PATH/data_download_publish/hist_skip_no_zero.py "temp-outputfile.tif" 1 2 94 "temp-outputfile_band_1.tif"
	      python $_CIOP_APPLICATION_PATH/data_download_publish/hist_skip_no_zero.py "temp-outputfile.tif" 2 2 94 "temp-outputfile_band_2.tif"
	      python $_CIOP_APPLICATION_PATH/data_download_publish/hist_skip_no_zero.py "temp-outputfile.tif" 3 2 94 "temp-outputfile_band_3.tif"
              # remove temp file
              rm temp-outputfile.tif
	      # merge bands to create RGB+ALPHA
              gdal_merge.py -separate -n 0 -a_nodata 0 -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" "temp-outputfile_band_1.tif" "temp-outputfile_band_2.tif" "temp-outputfile_band_3.tif" -o ${TMPDIR}/temp-outputfile.tif
	      # remove temp files
              rm temp-outputfile_band_1.tif temp-outputfile_band_2.tif temp-outputfile_band_3.tif
              # re-projection
              gdalwarp -ot Byte -t_srs EPSG:3857 -srcnodata 0 -dstnodata 0 -dstalpha -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" ${TMPDIR}/temp-outputfile.tif ${outputfile}
              returnCode=$?
              [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
              #Add overviews
              gdaladdo -r average ${outputfile} 2 4 8 16
              returnCode=$?
              [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
              # remove temp files
              rm ${TMPDIR}/temp-outputfile.tif
              # move result to output folder
              mv ${outputfile} ${OUTPUTDIR}/
          done
          
          cd - 2>/dev/null
      else
          ciop-log "ERROR" "The retrieved ${mission} product is not a directory"
          return ${ERR_GETDATA}
      fi
  fi


  if [[ "${mission}" == "Alos-2" ]]; then
      # check if ALOS2 product is a folder
      if [[ -d "${retrievedProduct}" ]]; then
          # check if ALOS2 folder contains a zip file
          ALOS_ZIP=$(ls ${retrievedProduct} | egrep '^.*ALOS2.*.zip$')
	  cd ${retrievedProduct}
          # if doesn't contain a zip it should be already uncompressed
          [[ -z "$ALOS_ZIP" ]] || unzip $ALOS_ZIP
          test_tif_present=$(ls *.tif)
          [[ "${test_tif_present}" == "" ]] && (ciop-log "ERROR - empty product folder"; return ${ERR_GETDATA})
	  for img in *.tif ; do
	      ciop-log "INFO" "Reprojecting "$mission" image: $img"
              gdalwarp -ot UInt16 -srcnodata 0 -dstnodata 0 -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -t_srs EPSG:3857 ${img} temp-outputfile.tif
              returnCode=$?
              [ $returnCode -eq 0 ] || return ${ERR_CONVERT}

	      ciop-log "INFO" "Converting to dB "$mission" image: $img"
	      #prepare snap request file for linear to dB conversion 
   	      SNAP_REQUEST=$( create_snap_request_linear_to_dB "${retrievedProduct}/temp-outputfile.tif" "${retrievedProduct}/temp-outputfile2.tif" )
   	      [ $? -eq 0 ] || return ${SNAP_REQUEST_ERROR}
	      [ $DEBUG -eq 1 ] && cat ${SNAP_REQUEST}
   	      # invoke the ESA SNAP toolbox
  	      gpt ${SNAP_REQUEST} -c "${CACHE_SIZE}" &> /dev/null
   	      # check the exit code
   	      [ $? -eq 0 ] || return $ERR_SNAP
			
	      ciop-log "INFO" "Scaling and alpha band addition to "$mission" image: $img"
              # histogram skip (percentiles from 2 to 95) on separated bands
              python $_CIOP_APPLICATION_PATH/data_download_publish/hist_skip_no_zero.py "temp-outputfile2.tif" 1 2 98 "temp-outputfile3.tif"
              # reprojection
	      gdalwarp -ot Byte -srcnodata 0 -dstnodata 0 -dstalpha -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "ALPHA=YES" -t_srs EPSG:3857 temp-outputfile3.tif ${OUTPUTDIR}/${img}
	      returnCode=$?
              [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
              rm -f temp-outputfile*

	      gdaladdo -r average ${OUTPUTDIR}/${img} 2 4 8 16
	      returnCode=$?
	      [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
	  done
          cd -
      fi
  fi

  if [[ "${mission}" == "Kompsat-5" ]]; then
      if [[ -d "${retrievedProduct}" ]]; then
          img=$(find ${retrievedProduct}/ -name ${productName}.tif)
          #local minVal=1
          #local maxVal=500
         # python $_CIOP_APPLICATION_PATH/data_download_publish/linear_stretch.py "${img}" 1 "${minVal}" "${maxVal}" "temp-outputfile.tif"
          # linear stretching between values tailored on mission data
          python $_CIOP_APPLICATION_PATH/data_download_publish/hist_skip_no_zero.py "${img}" 1 2 96 "temp-outputfile.tif"

          ciop-log "INFO" "Reprojecting and alpha band addition to "$mission" image: $img"
          outputfile=${TMPDIR}/${productName}.tif
          # re-projection
          gdalwarp -ot Byte -t_srs EPSG:3857 -srcnodata 0 -dstnodata 0 -dstalpha -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "ALPHA=YES" temp-outputfile.tif ${outputfile}
          returnCode=$?
          [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
          # remove temp files
          rm temp-outputfile.tif
  
          #Add overviews
          gdaladdo -r average ${outputfile} 2 4 8 16
          returnCode=$?
          [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
          # move result to output folder
          mv ${outputfile} ${OUTPUTDIR}/
          
      else
          ciop-log "ERROR" "The retrieved ${mission} product is not a directory"
          return ${ERR_GETDATA}
      fi
  fi

  if [[ "${mission}" == "TerraSAR-X" ]]; then
	IMAGEDATA=""
	if [[ -d "${retrievedProduct}" ]]; then
		#tsx_xml=$(find ${retrievedProduct}/ -name '*SAR*.xml' | head -1 | sed 's|^.*\/||')
		IMAGEDATA=$(find ${retrievedProduct} -name 'IMAGEDATA')
		if [[ -z "$IMAGEDATA" ]]; then 
			ciop-log "ERROR" "Failed to get IMAGEDATA dir"
			return ${ERR_CONVERT}
		fi
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
	fi
	cd $IMAGEDATA
	for img in *.tif ; do
                ciop-log "INFO" "Reprojecting "$mission" image: $img"
                gdalwarp -ot UInt16 -srcnodata 0 -dstnodata 0 -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -t_srs EPSG:3857 ${img} temp-outputfile.tif
                returnCode=$?
                [ $returnCode -eq 0 ] || return ${ERR_CONVERT}

                ciop-log "INFO" "Scaling and alpha band addition to "$mission" image: $img"
                # histogram skip (percentiles from 2 to 96) 
                python $_CIOP_APPLICATION_PATH/data_download_publish/hist_skip_no_zero.py "temp-outputfile.tif" 1 2 96 "temp-outputfile2.tif"
                # reprojection
                gdalwarp -ot Byte -srcnodata 0 -dstnodata 0 -dstalpha -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "ALPHA=YES" -t_srs EPSG:3857 temp-outputfile2.tif ${OUTPUTDIR}/${img}
                returnCode=$?
                [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
                rm -f temp-outputfile*

                gdaladdo -r average ${OUTPUTDIR}/${img} 2 4 8 16
                returnCode=$?
                [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
		
	done
	cd -
	if [[ "${retrievedProduct##*.}" == "tar" ]]; then
		rm -rf temp
	fi
  fi

  if [[ "${mission}" == "UK-DMC2" ]]; then
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

  if [[ "${mission}" == "Resurs-P" ]] || [[ "${mission}" == "Kanopus-V" ]]; then
      ### !!! TO-DO: update once reference Resurs-P info, doc and samples are provided !!! ###
      local tif_file=""
      # input file dependon mission
      if [[ "${mission}" == "Resurs-P" ]] ; then
          tif_file=$(find ${retrievedProduct} -name '*.tiff')
      elif  [[ "${mission}" == "Kanopus-V" ]] ; then
          tif_file=$(find ${retrievedProduct} -name '*.tiff')
      fi
      tif2check=""
      # check if there are more than one tif (case when also the panchromatic product is present)
      tifProdArr=($tif_file)
      tifProdArr_num=${#tifProdArr[@]}
      if [ $tifProdArr_num -eq 0 ]; then
          ciop-log "ERROR" "No tif product found"
          return ${ERR_CONVERT}
      elif [ $tifProdArr_num -eq 1 ]; then
          tif2check=${tif_file}
      # get multispectral product as default
      else
          let "tifProdArr_num-=1"
          for idTmp in `seq 0 $tifProdArr_num`;
          do
              num_bands=$(get_bands_num_tif "${tifProdArr[$idTmp]}")
              retCode=$?
              [ $retCode -eq 0 ] || return ${retCode}
              if [ $num_bands -gt 1 ]; then
                  tif2check=${tifProdArr[$idTmp]}
                  break
              fi
          done
      fi
      bandsNum=$(get_bands_num_tif "${tif2check}")
      retCode=$?
      [ $retCode -eq 0 ] || return ${retCode}
      [ $bandsNum -eq 1 ] && return ${ERR_PAN} || tif_file=${tif2check}
      outputfile=${tif_file##*/}; outputfile=${outputfile%.tiff}.tif
      ciop-log "INFO" "Processing Tiff file: $tif_file"
      # histogram skip (percentiles from 2 to 96) on separated bands
      python $_CIOP_APPLICATION_PATH/data_download_publish/hist_skip_no_zero.py "${tif_file}" 3 2 96 "temp-outputfile_band_r.tif"
      python $_CIOP_APPLICATION_PATH/data_download_publish/hist_skip_no_zero.py "${tif_file}" 2 2 96 "temp-outputfile_band_g.tif"
      python $_CIOP_APPLICATION_PATH/data_download_publish/hist_skip_no_zero.py "${tif_file}" 1 2 96 "temp-outputfile_band_b.tif"
      gdal_merge.py -separate -n 0 -a_nodata 0 -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" "temp-outputfile_band_r.tif" "temp-outputfile_band_g.tif" "temp-outputfile_band_b.tif" -o ${TMPDIR}/temp-outputfile.tif
      # rm temp files
      rm temp-outputfile_band_r.tif temp-outputfile_band_g.tif temp-outputfile_band_b.tif
      # re-projection
      gdalwarp -ot Byte -t_srs EPSG:3857 -srcnodata 0 -dstnodata 0 -dstalpha -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" ${TMPDIR}/temp-outputfile.tif ${OUTPUTDIR}/${outputfile}
      returnCode=$?
      [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
      # rm temp files
      rm ${TMPDIR}/temp-outputfile.tif
      # add overviews
      gdaladdo -r average ${OUTPUTDIR}/${outputfile} 2 4 8 16
      returnCode=$?
      [ $returnCode -eq 0 ] || return ${ERR_CONVERT}

  fi


  if [[ "${mission}" == "Radarsat-2" ]]; then
      if [[ -d "${retrievedProduct}" ]]; then
          product_xml=$(find ${retrievedProduct}/ -name 'product.xml')
          ciop-log "DEBUG" "product_xml ${product_xml}"
          #get band co-pol from product name
          bandCoPol=""
          if [[ $( echo ${productName} | grep "HH" ) != "" ]] ; then
              bandCoPol="Sigma0_HH_db"
          elif [[ $( echo ${productName} | grep "VV" ) != "" ]]; then
              bandCoPol="Sigma0_VV_db"
          else
              return ${ERR_WRONGPOLARIZATION}
          fi
          # get pixel spacing from product_xml
          pixelSpacing=$( cat ${product_xml} | grep sampledPixelSpacing | sed -n -e 's|^.*<sampledPixelSpacing .*>\(.*\)</sampledPixelSpacing>|\1|p' )
          ml=1
          outProd=${TMPDIR}/rs2_cal_tc_db_co_pol
          outProdTIF=${outProd}.tif
          # prepare the SNAP request
          SNAP_REQUEST=$( create_snap_request_cal_ml_tc_db_scale_byte_rs2 "${product_xml}" "${bandCoPol}" "${ml}" "${pixelSpacing}" "${outProd}" )
          [ $? -eq 0 ] || return ${SNAP_REQUEST_ERROR}
          [ $DEBUG -eq 1 ] && cat ${SNAP_REQUEST}
          # report activity in the log
          ciop-log "INFO" "Generated request file: ${SNAP_REQUEST}"
          # report activity in the log
          ciop-log "INFO" "Invoking SNAP-gpt on the generated request file for calibration [multilook] terrain correction and dB conversion"
          # invoke the ESA SNAP toolbox
          gpt $SNAP_REQUEST -c "${CACHE_SIZE}" &> /dev/null
          # check the exit code
          [ $? -eq 0 ] || return $ERR_SNAP
          
	  ciop-log "INFO" "Reprojecting and alpha band addition to "$mission" image: $productName"
          gdalwarp -ot Byte -srcnodata 0 -dstnodata 0 -dstalpha -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "ALPHA=YES" -t_srs EPSG:3857 ${outProdTIF} ${OUTPUTDIR}/${productName}.tif
          returnCode=$?
          [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
          #add overlay
          gdaladdo -r average ${OUTPUTDIR}/${productName}.tif 2 4 8 16
          returnCode=$?
          [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
          # cleanup
          rm -f ${outProdTIF} 
      else
          ciop-log "ERROR" "The retrieved product ${retrievedProduct} is not a directory or does not exist"
          return ${ERR_UNPACKING}
      fi
  fi


  if [[ "${mission}" == "GF2" ]]; then
      filename="${retrievedProduct##*/}"; ext="${filename#*.}"
      # check extension, uncrompress and get product name
      if [[ "$ext" == "tar" ]]; then
          ciop-log "INFO" "Extracting $retrievedProduct"
          currentBasename=$(basename $retrievedProduct)
          currentBasename="${currentBasename%%.*}"
          mkdir -p ${retrievedProduct%/*}/${currentBasename}
          cd ${retrievedProduct%/*}
          tar xf $filename -C ${currentBasename}
          returnCode=$?
          [ $returnCode -eq 0 ] || return ${ERR_UNPACKING}
          prodname=${retrievedProduct%/*}/${currentBasename}
          prodBasename=$(basename ${prodname})
          # get multispectral tif product 
          mss_product=$(ls "${prodname}"/*MSS2.tiff)
      else
          return ${ERR_GETDATA}
      fi
      #define output filename
      outputfile=${prodBasename}.tif
      # create full resolution tif image with Red=B4(NIR) Green=B3(RED) Blue=B2(GREEN)
      # histogram skip (percentiles from 2 to 96) on separated bands
      python $_CIOP_APPLICATION_PATH/data_download_publish/hist_skip_no_zero.py "${mss_product}" 4 2 96 "temp-outputfile_band_r.tif"
      python $_CIOP_APPLICATION_PATH/data_download_publish/hist_skip_no_zero.py "${mss_product}" 3 2 96 "temp-outputfile_band_g.tif"
      python $_CIOP_APPLICATION_PATH/data_download_publish/hist_skip_no_zero.py "${mss_product}" 2 2 96 "temp-outputfile_band_b.tif"
      # merge RGB bands
      gdal_merge.py -separate -n 0 -a_nodata 0 -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" "temp-outputfile_band_r.tif" "temp-outputfile_band_g.tif" "temp-outputfile_band_b.tif" -o ${TMPDIR}/temp-outputfile.tif
      # rm temp files
      rm temp-outputfile_band_r.tif temp-outputfile_band_g.tif temp-outputfile_band_b.tif
      # re-projection
      gdalwarp -ot Byte -t_srs EPSG:3857 -srcnodata 0 -dstnodata 0 -dstalpha -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" ${TMPDIR}/temp-outputfile.tif ${OUTPUTDIR}/${outputfile}
      returnCode=$?
      [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
      # rm temp files
      rm ${TMPDIR}/temp-outputfile.tif
      #Add overviews
      gdaladdo -r average ${OUTPUTDIR}/$outputfile 2 4 8 16
      returnCode=$?
      [ $returnCode -eq 0 ] || return ${ERR_CONVERT}      
  fi

  if [[ "${mission}" == "RapidEye" ]]; then
      tifProd=$(find ${retrievedProduct}/ -name ${productName}.tif)
      [[ "${tifProd}" == "" ]] && return ${ERR_GETDATA}
      # create full resolution tif image with Red=B3 Green=B2 Blue=B1
      pconvert -b 3,2,1 -f tif -o ${TMPDIR} ${tifProd} &> /dev/null
      # check the exit code
      [ $? -eq 0 ] || return $ERR_PCONVERT
      # get output filename genarated by pconvert
      pconvert_out=${TMPDIR}/${productName}.tif
      #define output filename
      outputfile=${OUTPUTDIR}/${productName}.tif
      # run gdalwarp for product reprojection
      gdalwarp -ot Byte -t_srs EPSG:3857 -srcalpha -dstalpha -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" ${pconvert_out} ${outputfile}      
      returnCode=$?
      [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
      #Remove temporary file
      rm -f $pconvert_out
      #Add overviews
      gdaladdo -r average ${outputfile} 2 4 8 16
      returnCode=$?
      [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
  fi

  if [[ "${mission}" == "VRSS1" ]]; then
      filename="${retrievedProduct##*/}"; ext="${filename#*.}"
      prod_dir=""
      # assumption is that the product has .tar extension or is already uncompressed
      if  [[ "$ext" == "tar" ]]; then
      # if tar uncompress the product
          ciop-log "INFO" "Running command: tar xf $retrievedProduct"
          tar xf $retrievedProduct -C ${TMPDIR}
          returnCode=$?
          [ $returnCode -eq 0 ] || return ${ERR_GETDATA}
          prod_dir=${TMPDIR}
      else
          #already uncrompressed
          prod_dir=${retrievedProduct}
      fi
      # find the red band = B3
      RED=$(find ${prod_dir}/ -name '*_3.tif')
      [[ "${RED}" == "" ]] && return ${ERR_GETDATA}
      # find the green band = B2
      GREEN=$(find ${prod_dir}/ -name '*_2.tif')
      [[ "${GREEN}" == "" ]] && return ${ERR_GETDATA}
      # find the blue band = B1
      BLUE=$(find ${prod_dir}/ -name '*_1.tif')
      [[ "${BLUE}" == "" ]] && return ${ERR_GETDATA}
      #define output filename
      outputfile=$(basename ${BLUE} | sed -n -e 's|\(.*\)_1.tif|\1|p')
      outputfile=${OUTPUTDIR}/${outputfile}.tif

      # histogram skip (percentiles from 2 to 96) on separated bands
      python $_CIOP_APPLICATION_PATH/data_download_publish/hist_skip_no_zero.py "${RED}" 1 2 96 "temp-outputfile_band_r.tif"
      python $_CIOP_APPLICATION_PATH/data_download_publish/hist_skip_no_zero.py "${GREEN}" 1 2 96 "temp-outputfile_band_g.tif"
      python $_CIOP_APPLICATION_PATH/data_download_publish/hist_skip_no_zero.py "${BLUE}" 1 2 96 "temp-outputfile_band_b.tif"
      # Merge RGB bands in a single GeoTiff
      gdal_merge.py -separate -n 0 -a_nodata 0 -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" "temp-outputfile_band_r.tif" "temp-outputfile_band_g.tif" "temp-outputfile_band_b.tif" -o ${TMPDIR}/temp-outputfile.tif
      # remove temp files
      rm temp-outputfile_band_r.tif temp-outputfile_band_g.tif temp-outputfile_band_b.tif
      # re-projection
      gdalwarp -ot Byte -t_srs EPSG:3857 -srcnodata 0 -dstnodata 0 -dstalpha -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" ${TMPDIR}/temp-outputfile.tif ${outputfile}
      returnCode=$?
      # remove temp files
      rm ${TMPDIR}/temp-outputfile.tif

      #Add overviews
      gdaladdo -r average ${outputfile} 2 4 8 16
      returnCode=$?
      [ $returnCode -eq 0 ] || return ${ERR_CONVERT}    
  fi

  return 0

}


# Functioon to get number of bands embedded in a tif file
function get_bands_num_tif() {
#function call num_bands=$(get_bands_num_tif "${inputTIF}")

# get number of inputs
inputNum=$#
# check on number of inputs
if [ "$inputNum" -ne "1" ] ; then
    return ${ERR_GET_BANDS_NUM}
fi

local inputTIF=$1
local num_bands=0
# use gdalinfo to get band indexes list and put it in an array
bandId_list=$(gdalinfo ${inputTIF} | grep Band | sed -n -e 's|^.*Band \(.*\)Block.*|\1|p')
bandId_array=($bandId_list)
# number of bands is equal to array size
num_bands=${#bandId_array[@]}
[ $num_bands -gt 0 ] && {
    echo "${num_bands}"
    return 0
} || return ${ERR_GET_BANDS_NUM}

}

function create_snap_request_rad2refl_reproj_s3(){

inputNum=$#
[ "$inputNum" -ne 2 ] && return ${ERR_PREPROCESS}

local target=$1
local input=$2

#sets the output filename
snap_request_filename="${TMPDIR}/$( uuidgen ).xml"
cat << EOF > ${snap_request_filename}
<graph id="Graph">
  <version>1.0</version>
  <node id="Read">
    <operator>Read</operator>
    <sources/>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <file>${input}</file>
    </parameters>
  </node>
  <node id="Rad2Refl">
    <operator>Rad2Refl</operator>
    <sources>
      <sourceProduct refid="Read"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <sensor>OLCI</sensor>
      <conversionMode>RAD_TO_REFL</conversionMode>
      <copyTiePointGrids>false</copyTiePointGrids>
      <copyFlagBandsAndMasks>false</copyFlagBandsAndMasks>
      <copyNonSpectralBands>false</copyNonSpectralBands>
    </parameters>
  </node>
  <node id="Reproject">
    <operator>Reproject</operator>
    <sources>
      <sourceProduct refid="Rad2Refl"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <wktFile/>
      <crs>PROJCS[&quot;WGS 84 / Pseudo-Mercator&quot;, &#xd;
  GEOGCS[&quot;WGS 84&quot;, &#xd;
    DATUM[&quot;World Geodetic System 1984&quot;, &#xd;
      SPHEROID[&quot;WGS 84&quot;, 6378137.0, 298.257223563, AUTHORITY[&quot;EPSG&quot;,&quot;7030&quot;]], &#xd;
      AUTHORITY[&quot;EPSG&quot;,&quot;6326&quot;]], &#xd;
    PRIMEM[&quot;Greenwich&quot;, 0.0, AUTHORITY[&quot;EPSG&quot;,&quot;8901&quot;]], &#xd;
    UNIT[&quot;degree&quot;, 0.017453292519943295], &#xd;
    AXIS[&quot;Geodetic longitude&quot;, EAST], &#xd;
    AXIS[&quot;Geodetic latitude&quot;, NORTH], &#xd;
    AUTHORITY[&quot;EPSG&quot;,&quot;4326&quot;]], &#xd;
  PROJECTION[&quot;Popular Visualisation Pseudo Mercator&quot;, AUTHORITY[&quot;EPSG&quot;,&quot;1024&quot;]], &#xd;
  PARAMETER[&quot;semi_minor&quot;, 6378137.0], &#xd;
  PARAMETER[&quot;latitude_of_origin&quot;, 0.0], &#xd;
  PARAMETER[&quot;central_meridian&quot;, 0.0], &#xd;
  PARAMETER[&quot;scale_factor&quot;, 1.0], &#xd;
  PARAMETER[&quot;false_easting&quot;, 0.0], &#xd;
  PARAMETER[&quot;false_northing&quot;, 0.0], &#xd;
  UNIT[&quot;m&quot;, 1.0], &#xd;
  AXIS[&quot;Easting&quot;, EAST], &#xd;
  AXIS[&quot;Northing&quot;, NORTH], &#xd;
  AUTHORITY[&quot;EPSG&quot;,&quot;3857&quot;]]</crs>
      <resampling>Nearest</resampling>
      <referencePixelX/>
      <referencePixelY/>
      <easting/>
      <northing/>
      <orientation/>
      <pixelSizeX/>
      <pixelSizeY/>
      <width/>
      <height/>
      <tileSizeX/>
      <tileSizeY/>
      <orthorectify>false</orthorectify>
      <elevationModelName/>
      <noDataValue>NaN</noDataValue>
      <includeTiePointGrids>true</includeTiePointGrids>
      <addDeltaBands>false</addDeltaBands>
    </parameters>
  </node>
  <node id="Write">
    <operator>Write</operator>
    <sources>
      <sourceProduct refid="Reproject"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <file>${target}</file>
      <formatName>GeoTIFF-BigTIFF</formatName>
    </parameters>
  </node>
  <applicationData id="Presentation">
    <Description/>
    <node id="Read">
            <displayPosition x="37.0" y="134.0"/>
    </node>
    <node id="Rad2Refl">
      <displayPosition x="166.0" y="132.0"/>
    </node>
    <node id="Reproject">
      <displayPosition x="296.0" y="132.0"/>
    </node>
    <node id="Write">
            <displayPosition x="455.0" y="135.0"/>
    </node>
  </applicationData>
</graph>/graph>
EOF

[ $? -eq 0 ] && {
        echo "${snap_request_filename}"
        return 0
} || return ${SNAP_REQUEST_ERROR}

}
 
function create_snap_request_cal_ml_tc_db_scale_byte_rs2(){

# function call create_snap_request_cal_ml_tc_d "${product_xml}" "${bandCoPol}" "${ml}" "${pixelSpacing}" "${outProd}" 

# function which creates the actual request from
# a template and returns the path to the request

inputNum=$#
[ "$inputNum" -ne 5 ] && return ${ERR_PREPROCESS}

local prodname=$1
local bandCoPol=$2
local ml_factor=$3
local pixelSpacing=$4
local outprod=$5

local commentMlBegin=""
local commentMlEnd=""
local commentCalSrcBegin=""
local commentCalSrcEnd=""

local beginCommentXML="<!--"
local endCommentXML="-->"


if [ "$ml_factor" -eq 1 ] ; then
    commentMlBegin="${beginCommentXML}"
    commentMlEnd="${endCommentXML}"
else
    pixelSpacing=$(echo "scale=0; $ml_factor*$pixelSpacing" | bc )
    commentCalSrcBegin="${beginCommentXML}"
    commentCalSrcEnd="${endCommentXML}"
fi

#sets the output filename
snap_request_filename="${TMPDIR}/$( uuidgen ).xml"
cat << EOF > ${snap_request_filename}
<graph id="Graph">
  <version>1.0</version>
  <node id="Read">
    <operator>Read</operator>
    <sources/>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <file>${prodname}</file>
    </parameters>
  </node>
  <node id="Calibration">
    <operator>Calibration</operator>
    <sources>
      <sourceProduct refid="Read"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <sourceBands/>
      <auxFile>Product Auxiliary File</auxFile>
      <externalAuxFile/>
      <outputImageInComplex>false</outputImageInComplex>
      <outputImageScaleInDb>false</outputImageScaleInDb>
      <createGammaBand>false</createGammaBand>
      <createBetaBand>false</createBetaBand>
      <selectedPolarisations/>
      <outputSigmaBand>true</outputSigmaBand>
      <outputGammaBand>false</outputGammaBand>
      <outputBetaBand>false</outputBetaBand>
    </parameters>
  </node>
${commentMlBegin}  <node id="Multilook">
    <operator>Multilook</operator>
    <sources>
      <sourceProduct refid="Calibration"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <sourceBands/>
      <nRgLooks>${ml_factor}</nRgLooks>
      <nAzLooks>${ml_factor}</nAzLooks>
      <outputIntensity>true</outputIntensity>
      <grSquarePixel>true</grSquarePixel>
    </parameters>
  </node> ${commentMlEnd}
  <node id="Terrain-Correction">
    <operator>Terrain-Correction</operator>
    <sources>
${commentMlBegin}  <sourceProduct refid="Multilook"/> ${commentMlEnd}
${commentCalSrcBegin}  <sourceProduct refid="Calibration"/> ${commentCalSrcEnd}
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <sourceBands/>
      <demName>SRTM 3Sec</demName>
      <externalDEMFile/>
      <externalDEMNoDataValue>0.0</externalDEMNoDataValue>
      <externalDEMApplyEGM>true</externalDEMApplyEGM>
      <demResamplingMethod>BILINEAR_INTERPOLATION</demResamplingMethod>
      <imgResamplingMethod>BILINEAR_INTERPOLATION</imgResamplingMethod>
      <pixelSpacingInMeter>${pixelSpacing}</pixelSpacingInMeter>
      <!-- <pixelSpacingInDegree>2.2457882102988038E-4</pixelSpacingInDegree> -->
      <mapProjection>GEOGCS[&quot;WGS84(DD)&quot;, &#xd;
  DATUM[&quot;WGS84&quot;, &#xd;
    SPHEROID[&quot;WGS84&quot;, 6378137.0, 298.257223563]], &#xd;
  PRIMEM[&quot;Greenwich&quot;, 0.0], &#xd;
  UNIT[&quot;degree&quot;, 0.017453292519943295], &#xd;
  AXIS[&quot;Geodetic longitude&quot;, EAST], &#xd;
  AXIS[&quot;Geodetic latitude&quot;, NORTH]]</mapProjection>
      <nodataValueAtSea>false</nodataValueAtSea>
      <saveDEM>false</saveDEM>
      <saveLatLon>false</saveLatLon>
      <saveIncidenceAngleFromEllipsoid>false</saveIncidenceAngleFromEllipsoid>
      <saveLocalIncidenceAngle>false</saveLocalIncidenceAngle>
      <saveProjectedLocalIncidenceAngle>false</saveProjectedLocalIncidenceAngle>
      <saveSelectedSourceBand>true</saveSelectedSourceBand>
      <outputComplex>false</outputComplex>
      <applyRadiometricNormalization>false</applyRadiometricNormalization>
      <saveSigmaNought>false</saveSigmaNought>
      <saveGammaNought>false</saveGammaNought>
      <saveBetaNought>false</saveBetaNought>
      <incidenceAngleForSigma0>Use projected local incidence angle from DEM</incidenceAngleForSigma0>
      <incidenceAngleForGamma0>Use projected local incidence angle from DEM</incidenceAngleForGamma0>
      <auxFile>Latest Auxiliary File</auxFile>
      <externalAuxFile/>
    </parameters>
  </node>
  <node id="LinearToFromdB">
    <operator>LinearToFromdB</operator>
    <sources>
      <sourceProduct refid="Terrain-Correction"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <sourceBands/>
    </parameters>
  </node>
  <node id="BandSelect">
    <operator>BandSelect</operator>
    <sources>
      <sourceProduct refid="LinearToFromdB"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <selectedPolarisations/>
      <sourceBands>${bandCoPol}</sourceBands>
      <bandNamePattern/>
    </parameters>
  </node>
  <node id="BandMaths">
    <operator>BandMaths</operator>
    <sources>
      <sourceProduct refid="BandSelect"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <targetBands>
        <targetBand>
          <name>clipped</name>
          <type>float32</type>
          <expression>if fneq(${bandCoPol},0.0) then (if ${bandCoPol}&lt;=-15 then -15 else (if ${bandCoPol}&gt;=5 then 5 else ${bandCoPol})) else NaN</expression>
          <description/>
          <unit/>
          <noDataValue>NaN</noDataValue>
        </targetBand>
      </targetBands>
      <variables/>
    </parameters>
  </node>
  <node id="BandMaths(2)">
    <operator>BandMaths</operator>
    <sources>
      <sourceProduct refid="BandMaths"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <targetBands>
        <targetBand>
          <name>quantized</name>
          <type>uint8</type>
          <expression>if !nan(clipped) then floor(clipped*12.7+191.5) else NaN</expression>
          <description/>
          <unit/>
          <noDataValue>NaN</noDataValue>
        </targetBand>
      </targetBands>
      <variables/>
    </parameters>
  </node>
  <node id="Write">
    <operator>Write</operator>
    <sources>
      <sourceProduct refid="BandMaths(2)"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <file>${outprod}</file>
      <formatName>GeoTIFF-BigTIFF</formatName>
    </parameters>
  </node>
  <applicationData id="Presentation">
    <Description/>
    <node id="Read">
            <displayPosition x="37.0" y="134.0"/>
    </node>
    <node id="Calibration">
      <displayPosition x="118.0" y="135.0"/>
    </node>
    <node id="Multilook">
      <displayPosition x="211.0" y="135.0"/>
    </node>
    <node id="Terrain-Correction">
      <displayPosition x="300.0" y="135.0"/>
    </node>
    <node id="LinearToFromdB">
      <displayPosition x="454.0" y="134.0"/>
    </node>
    <node id="Write">
            <displayPosition x="628.0" y="137.0"/>
    </node>
  </applicationData>
</graph>
EOF

[ $? -eq 0 ] && {
    echo "${snap_request_filename}"
    return 0
} || return ${SNAP_REQUEST_ERROR}

}


function create_snap_request_linear_to_dB(){
# function call: create_snap_request_linear_to_dB "${inputfileTIF}" "${outputfileTIF}" 

# function which creates the actual request from
# a template and returns the path to the request

# get number of inputs
inputNum=$#
# check on number of inputs
if [ "$inputNum" -ne "2" ] ; then
    return ${SNAP_REQUEST_ERROR}
fi

local inputfileTIF=$1
local outputfileTIF=$2

#sets the output filename
snap_request_filename="${TMPDIR}/$( uuidgen ).xml"

cat << EOF > ${snap_request_filename}
<graph id="Graph">
  <version>1.0</version>
  <node id="Read">
    <operator>Read</operator>
    <sources/>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <file>${inputfileTIF}</file>
    </parameters>
  </node>
  <node id="BandMaths">
    <operator>BandMaths</operator>
    <sources>
      <sourceProduct refid="Read"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <targetBands>
        <targetBand>
          <name>band_1</name>
          <type>uint8</type>
          <expression>if fneq(band_1,0) then max(20*log10(band_1),1) else 0</expression>
          <description/>
          <unit/>
          <noDataValue>0.0</noDataValue>
        </targetBand>
      </targetBands>
      <variables/>
    </parameters>
  </node>
  <node id="Write">
    <operator>Write</operator>
    <sources>
      <sourceProduct refid="BandMaths"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <file>${outputfileTIF}</file>
      <formatName>GeoTIFF-BigTIFF</formatName>
    </parameters>
  </node>
  <applicationData id="Presentation">
    <Description/>
    <node id="Read">
            <displayPosition x="37.0" y="134.0"/>
    </node>
    <node id="BandMaths">
      <displayPosition x="247.0" y="132.0"/>
    </node>
    <node id="Write">
            <displayPosition x="455.0" y="135.0"/>
    </node>
  </applicationData>
</graph>
EOF

    [ $? -eq 0 ] && {
        echo "${snap_request_filename}"
        return 0
    } || return ${SNAP_REQUEST_ERROR}

}


function create_snap_request_linear_stretching(){
# function call: create_snap_request_linear_stretching "${inputfileTIF}" "${sourceBandName}" "${linearCoeff}" "${offset}" "${min_out}" "${max_out}" "${outputfileTIF}"

# function which creates the actual request from
# a template and returns the path to the request

# get number of inputs
inputNum=$#
# check on number of inputs
if [ "$inputNum" -ne "7" ] ; then
    return ${SNAP_REQUEST_ERROR}
fi

local inputfileTIF=$1
local sourceBandName=$2
local linearCoeff=$3
local offset=$4
local min_out=$5
local max_out=$6
local outputfileTIF=$7

#sets the output filename
snap_request_filename="${TMPDIR}/$( uuidgen ).xml"

cat << EOF > ${snap_request_filename}
<graph id="Graph">
  <version>1.0</version>
  <node id="Read">
    <operator>Read</operator>
    <sources/>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <file>${inputfileTIF}</file>
    </parameters>
  </node>
  <node id="BandMaths">
    <operator>BandMaths</operator>
    <sources>
      <sourceProduct refid="Read"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <targetBands>
        <targetBand>
          <name>quantized</name>
          <type>uint8</type>
          <expression>if fneq(${sourceBandName},0) then max(min(floor(${sourceBandName}*${linearCoeff}+${offset}),${max_out}),${min_out}) else 0</expression>
          <description/>
          <unit/>
          <noDataValue>0</noDataValue>
        </targetBand>
      </targetBands>
      <variables/>
    </parameters>
  </node>
  <node id="Write">
    <operator>Write</operator>
    <sources>
      <sourceProduct refid="BandMaths"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <file>${outputfileTIF}</file>
      <formatName>GeoTIFF-BigTIFF</formatName>
    </parameters>
  </node>
  <applicationData id="Presentation">
    <Description/>
    <node id="Read">
            <displayPosition x="37.0" y="134.0"/>
    </node>
    <node id="BandMaths">
      <displayPosition x="472.0" y="131.0"/>
    </node>
    <node id="Write">
            <displayPosition x="578.0" y="133.0"/>
    </node>
  </applicationData>
</graph>
EOF
[ $? -eq 0 ] && {
    echo "${snap_request_filename}"
    return 0
    } || return ${SNAP_REQUEST_ERROR}

}


function create_snap_request_statsComputation(){
# function call: create_snap_request_statsComputation $tiffProduct $sourceBandName $outputStatsFile $pc_csv_list
    # get number of inputs
    inputNum=$#
    # check on number of inputs
    if [ "$inputNum" -lt "3" ] || [ "$inputNum" -gt "4" ]; then
        return ${SNAP_REQUEST_ERROR}
    fi

    local tiffProduct=$1
    local sourceBandName=$2
    local outputStatsFile=$3
    local pc_csv_list=""
    [ "$inputNum" -eq "3" ] && pc_csv_list="90,95" || pc_csv_list=$4
    #sets the output filename
    snap_request_filename="${TMPDIR}/$( uuidgen ).xml"

   cat << EOF > ${snap_request_filename}
<graph id="Graph">
  <version>1.0</version>
  <node id="StatisticsOp">
    <operator>StatisticsOp</operator>
    <sources>
      <sourceProducts></sourceProducts>
    </sources>
    <parameters>
      <sourceProductPaths>${tiffProduct}</sourceProductPaths>
      <shapefile></shapefile>
      <startDate></startDate>
      <endDate></endDate>
      <bandConfigurations>
        <bandConfiguration>
          <sourceBandName>${sourceBandName}</sourceBandName>
          <expression></expression>
          <validPixelExpression></validPixelExpression>
        </bandConfiguration>
      </bandConfigurations>
      <outputShapefile></outputShapefile>
      <outputAsciiFile>${outputStatsFile}</outputAsciiFile>
      <percentiles>${pc_csv_list}</percentiles>
      <accuracy>4</accuracy>
    </parameters>
  </node>
</graph>
EOF

    [ $? -eq 0 ] && {
        echo "${snap_request_filename}"
        return 0
    } || return ${SNAP_REQUEST_ERROR}

}


#function thta extract the min and max values from an input TIFF for the selected source band contained in it
function extract_min_max(){
# function call: extract_min_max $tiffProduct $sourceBandName 

# get number of inputs
inputNum=$#
# check on number of inputs
if [ "$inputNum" -ne "2" ] ; then
    return ${SNAP_REQUEST_ERROR}
fi

local tiffProduct=$1
local sourceBandName=$2
# report activity in the log
ciop-log "INFO" "Extracting min max from ${sourceBandName} contained in ${tiffProduct}"
# Build statistics file name
statsFile=${TMPDIR}/displacement.stats
# prepare the SNAP request
SNAP_REQUEST=$( create_snap_request_statsComputation "${tiffProduct}" "${sourceBandName}" "${statsFile}" )
[ $? -eq 0 ] || return ${SNAP_REQUEST_ERROR}
# report activity in the log
ciop-log "INFO" "Generated request file: ${SNAP_REQUEST}"
# report activity in the log
ciop-log "INFO" "Invoking SNAP-gpt on the generated request file for statistics extraction"
# invoke the ESA SNAP toolbox
gpt $SNAP_REQUEST -c "${CACHE_SIZE}" &> /dev/null
# check the exit code
[ $? -eq 0 ] || return $ERR_SNAP

# get maximum from stats file
maximum=$(cat "${statsFile}" | grep world | tr '\t' ' ' | tr -s ' ' | cut -d ' ' -f 5)
#get minimum from stats file
minimum=$(cat "${statsFile}" | grep world | tr '\t' ' ' | tr -s ' ' | cut -d ' ' -f 7)

rm ${statsFile}
echo ${minimum} ${maximum}
return 0

}


#function that extracts a couple of percentiles from an input TIFF for the selected source band contained in it
function extract_pc1_pc2(){
# function call: extract_pc1_pc2 $tiffProduct $sourceBandName $pc1 $pc2

# get number of inputs
inputNum=$#
# check on number of inputs
if [ "$inputNum" -ne "4" ] ; then
    return ${SNAP_REQUEST_ERROR}
fi

local tiffProduct=$1
local sourceBandName=$2
local pc1=$3
local pc2=$4
local pc_csv_list=${pc1},${pc2}
# report activity in the log
ciop-log "INFO" "Extracting percentiles ${pc1} and ${pc2} from ${sourceBandName} contained in ${tiffProduct}"
# Build statistics file name
statsFile=${TMPDIR}/temp.stats
# prepare the SNAP request
SNAP_REQUEST=$( create_snap_request_statsComputation "${tiffProduct}" "${sourceBandName}" "${statsFile}" "${pc_csv_list}" )
[ $? -eq 0 ] || return ${SNAP_REQUEST_ERROR}
# report activity in the log
ciop-log "INFO" "Generated request file: ${SNAP_REQUEST}"
# report activity in the log
ciop-log "INFO" "Invoking SNAP-gpt on the generated request file for statistics extraction"
# invoke the ESA SNAP toolbox
gpt $SNAP_REQUEST -c "${CACHE_SIZE}" &> /dev/null
# check the exit code
[ $? -eq 0 ] || return $ERR_SNAP

# get maximum from stats file
percentile_1=$(cat "${statsFile}" | grep world | tr '\t' ' ' | tr -s ' ' | cut -d ' ' -f 8)
#get minimum from stats file
percentile_2=$(cat "${statsFile}" | grep world | tr '\t' ' ' | tr -s ' ' | cut -d ' ' -f 9)

rm ${statsFile}
echo ${percentile_1} ${percentile_2}
return 0

}


# function that creates the properties file to be annexed to output product 
function add_metadata(){
# function call add_metadata ${OUTPUTDIR} ${mission} ${prodType} ${currentProduct} 
# get number of inputs
inputNum=$#
# check on number of inputs
if [ "$inputNum" -ne "5" ] ; then
    return ${ERR_METADATA}
fi
# init variables
local outdir=$1
local mission=$2
local prodType=$3
local ref=$4
local retrievedProduct=$5

# get product date from input catalogue reference
startdate="$( opensearch-client -f atom "${ref}" startdate)"
# check error in query: put empty value in case of errors
res=$?
[ $res -eq 0 ] || startdate=""
#  get orbit direction from input catalogue reference
orbitDirection="$( opensearch-client -f atom "${ref}" orbitDirection)"
# check error in query: put empty value in case of errors
res=$?
[ $res -eq 0 ] || orbitDirection=""
#  get track number from input catalogue reference
track="$( opensearch-client -f atom "${ref}" track)"
# get cloudcover info
retrieved_xml=$(find ${retrievedProduct}/ -name '*.xml' )
ciop-log "INFO" "Retrieved xml is ${retrieved_xml}"
cloudcover="$( xmlstarlet sel -N sentinel3="http://www.esa.int/safe/sentinel/sentinel-3/1.0" --net -t -v '//sentinel3:brightPixels/@percentage' -n "${retrieved_xml}" )"
# check error in query: put empty value in case of errors
res=$?
[ $res -eq 0 ] || track=""
#get name of tif product to be published
for out_prod in $(ls ${outdir}); do
    out_prod_basename=$(basename ${out_prod})
    out_prod_noext="${out_prod_basename%%.*}"
    out_properties=${outdir}/${out_prod_noext}.properties
# write properties file
cat << EOF > ${out_properties}
Service\ Name=Full Resolution Rasterization
Product\ Name=${out_prod_basename}
Mission=${mission}
Product\ Type=${prodType}
Acquisition\ Date=${startdate}
Orbit\ Direction=${orbitDirection}
Track\ Number=${track}
Cloudcover\ Percentage=${cloudcover}
EOF
done
return 0

}


# main function
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
    [ $DEBUG -eq 1 ] && which gdal_translate    
    [ $DEBUG -eq 1 ] && ls -l ${SNAP_HOME}
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
        # report activity in the log
        ciop-log "INFO" "Path of retrieved product: ${retrievedProduct}"
    	prodname=$( basename "$retrievedProduct" )
	# report activity in the log
    	ciop-log "INFO" "Retrieved product name: ${prodname}"
	
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
        ciop-log "INFO" "Checking product type"
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
        # report activity in the log
        # NOTE: it is assumed that the "generate_full_res_tif" function always provides results in $OUTPUTDIR
        # report activity in the log
	ciop-log "INFO" "Adding metadata for ${prodname}"
        add_metadata ${OUTPUTDIR} ${mission} ${prodType} ${currentProduct} ${retrievedProduct}
        returnCode=$?
        [ $returnCode -eq 0 ] || return $returnCode
        # Publish results 
	# NOTE: it is assumed that the "generate_full_res_tif" and add_metadata functions always provides results in $OUTPUTDIR 		
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
export DEBUG=0

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

