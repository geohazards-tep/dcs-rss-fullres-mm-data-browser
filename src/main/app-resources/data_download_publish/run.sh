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
ERR_WRONGPOLARIZATION=14
ERR_METADATA=15

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
      #naming convention K3_”Time”_”OrbNo”_"PassNo"_”ProcLevel”
      prodTypeName=${prodname:(-3)}
      if [[ "$prodTypeName" != "L1G" ]] ; then 
          return $ERR_WRONGPRODTYPE
      fi
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
	prodTypeName="Resurs-P"
  fi

  if [[ "${mission}" == "Kanopus-V" ]]; then
	prodTypeName=${prodname:10:3}
	[[ "$prodTypeName" != "MSS" ]] && return $ERR_WRONGPRODTYPE
  fi

  if [[ "${mission}" == "Kompsat-5" ]]; then
        #naming convention <K5>_<YYYYMMDDhhmmss>_<tttttt>_<nnnnn>_<o>_<MM><SS>_<PP>_<LLL> where LLL is the processing level
	prodTypeName=${prodname:47:3}
        [[ "$prodTypeName" != "L1D" ]] && return $ERR_WRONGPRODTYPE
  fi

  if [[ "${mission}" == "Radarsat-2" ]]; then
      #naming convention <RS2_BeamMode_Date_Time_Polarizations_ProcessingLevel>
      prodTypeName=${prodname:(-3)}
      [[ "$prodTypeName" != "SGF" ]] && return $ERR_WRONGPRODTYPE    
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
        ukdmc2_test=$(echo "${prod_basename}" | grep "UK-DMC-2")
        [ "${ukdmc2_test}" = "" ] || mission="UK-DMC-2"
        [ "${prod_basename_substr_8}" = "Resurs-P" ] && mission="Resurs-P"
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
        [ "${prod_basename_substr_4}" = "RS2_" ] && mission="Radarsat-2"
        
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


function create_snap_request_cal_ml_tc_db_scale_byte() {

# function call  "${s1_manifest}" "${bandCoPol}"  "${outProd}"

# function which creates the actual request from
# a template and returns the path to the request

inputNum=$#
[ "$inputNum" -ne 3 ] && return ${SNAP_REQUEST_ERROR}

local s1_manifest=$1
local bandCoPol=$2
local outProd=$3
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
  <node id="Multilook">
    <operator>Multilook</operator>
    <sources>
      <sourceProduct refid="Calibration"/>
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <sourceBands/>
      <nRgLooks>2</nRgLooks>
      <nAzLooks>2</nAzLooks>
      <outputIntensity>true</outputIntensity>
      <grSquarePixel>true</grSquarePixel>
    </parameters>
  </node>
  <node id="Terrain-Correction">
    <operator>Terrain-Correction</operator>
    <sources>
       <sourceProduct refid="Multilook"/> 
    </sources>
    <parameters class="com.bc.ceres.binding.dom.XppDomElement">
      <sourceBands/>
      <demName>SRTM 3Sec</demName>
      <externalDEMFile/>
      <externalDEMNoDataValue>0.0</externalDEMNoDataValue>
      <externalDEMApplyEGM>true</externalDEMApplyEGM>
      <demResamplingMethod>BILINEAR_INTERPOLATION</demResamplingMethod>
      <imgResamplingMethod>BILINEAR_INTERPOLATION</imgResamplingMethod>
      <pixelSpacingInMeter>20.0</pixelSpacingInMeter>
      <pixelSpacingInDegree>1.796630568239043E-4</pixelSpacingInDegree>
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
      outProd=${TMPDIR}/s1_cal_tc_db_co_pol
      outProdTIF=${outProd}.tif
      # prepare the SNAP request
      SNAP_REQUEST=$( create_snap_request_cal_ml_tc_db_scale_byte "${s1_manifest}" "${bandCoPol}"  "${outProd}")
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
      
      gdalwarp -ot Byte -t_srs EPSG:3857 -srcalpha -dstalpha -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "PHOTOMETRIC=RGB" -co "ALPHA=YES" ${OUTPUTDIR}/$tmp_outputfile ${OUTPUTDIR}/$outputfile
      returnCode=$?
      [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
      #rm -f temp-outputfile.tif

      #Remove temporary file
      rm -f ${OUTPUTDIR}/$tmp_outputfile
      rm -f ${OUTPUTDIR}/*.xml

      #Add overviews
      gdaladdo -r average ${OUTPUTDIR}/$outputfile 2 4 8 16
      returnCode=$?
      [ $returnCode -eq 0 ] || return ${ERR_CONVERT}            

  fi

  if [ ${mission} = "Landsat-8" ]; then

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
        if [[ -d "${retrievedProduct}" ]]; then
		#Select RGB bands
                RED=$(find ${retrievedProduct}/ -name 'K3_*_R.tif')
                GREEN=$(find ${retrievedProduct}/ -name 'K3_*_G.tif')
                BLUE=$(find ${retrievedProduct}/ -name  'K3_*_B.tif')

                mkdir -p ${retrievedProduct}/temp

		outputfile=${productName}.tif

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
	if [[ -d "${retrievedProduct}" ]]; then
		ALOS_ZIP=$(ls ${retrievedProduct} | egrep '^.*ALOS2.*.zip$')
		[[ -z "$ALOS_ZIP" ]] && ciop-log "ERROR" "Failed to get ALOS_ZIP"

		cd ${retrievedProduct}
		unzip $ALOS_ZIP
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
		   gdal_translate -scale -ot Byte -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "ALPHA=YES" temp-outputfile2.tif temp-outputfile3.tif
		   returnCode=$?
                   [ $returnCode -eq 0 ] || return ${ERR_CONVERT}		   
 
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
          #K5 needs to be translated otherwise SNAP cannot ingest it 
          ciop-log "INFO" "Tif format translation "$mission" image: $img"
          gdal_translate -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" ${img} temp-outputfile.tif
          returnCode=$?
          [ $returnCode -eq 0 ] || return ${ERR_CONVERT}

          ciop-log "INFO" "Converting to dB "$mission" image: $img"
          #prepare snap request file for linear to dB conversion
          SNAP_REQUEST=$( create_snap_request_linear_to_dB "temp-outputfile.tif" "temp-outputfile2.tif" )
          [ $? -eq 0 ] || return ${SNAP_REQUEST_ERROR}
          [ $DEBUG -eq 1 ] && cat ${SNAP_REQUEST}
          # invoke the ESA SNAP toolbox
          gpt ${SNAP_REQUEST} -c "${CACHE_SIZE}" &> /dev/null
          # check the exit code
          [ $? -eq 0 ] || return $ERR_SNAP
          #extract min max for better visualization
          tiffProduct=temp-outputfile2.tif
          sourceBandName=band_1
          #min max percentiles to be used in histogram stretching
          pc_min=2
          pc_max=95
          pc_min_max=$( extract_pc1_pc2 "temp-outputfile2.tif" $sourceBandName $pc_min $pc_max )
          [ $? -eq 0 ] || return ${ERR_CONVERT}
          # extract coefficient for linear stretching
          min_out=1
          max_out=255
          $_CIOP_APPLICATION_PATH/data_download_publish/linearEquationCoefficients.py ${pc_min_max} ${min_out} ${max_out} > ab.txt
          a=$( cat ab.txt | grep a | sed -n -e 's|^.*a=\(.*\)|\1|p')
          b=$( cat ab.txt | grep b |  sed -n -e 's|^.*b=\(.*\)|\1|p')

	  ciop-log "INFO" "Linear stretching of dB values "$mission" image: $img"
          SNAP_REQUEST=$( create_snap_request_linear_stretching "temp-outputfile2.tif" "${sourceBandName}" "${a}" "${b}" "${min_out}" "${max_out}" "temp-outputfile3.tif" )
          [ $? -eq 0 ] || return ${SNAP_REQUEST_ERROR}
          [ $DEBUG -eq 1 ] && cat ${SNAP_REQUEST}
          # invoke the ESA SNAP toolbox
          gpt ${SNAP_REQUEST} -c "${CACHE_SIZE}" &> /dev/null
          # check the exit code
          [ $? -eq 0 ] || return $ERR_SNAP

          ciop-log "INFO" "Reprojecting and alpha band addition to "$mission" image: $img"
          gdalwarp -ot Byte -srcnodata 0 -dstnodata 0 -dstalpha -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "ALPHA=YES" -t_srs EPSG:3857 temp-outputfile3.tif ${OUTPUTDIR}/${productName}.tif
          returnCode=$?
          [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
          rm -f temp-outputfile*
          #add overlay 
          gdaladdo -r average ${OUTPUTDIR}/${productName}.tif 2 4 8 16
          returnCode=$?
          [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
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

                ciop-log "INFO" "Converting to dB "$mission" image: $img"
                #prepare snap request file for linear to dB conversion
                SNAP_REQUEST=$( create_snap_request_linear_to_dB "temp-outputfile.tif" "temp-outputfile2.tif" )
                [ $? -eq 0 ] || return ${SNAP_REQUEST_ERROR}
                [ $DEBUG -eq 1 ] && cat ${SNAP_REQUEST}
                # invoke the ESA SNAP toolbox
                gpt ${SNAP_REQUEST} -c "${CACHE_SIZE}" &> /dev/null
                # check the exit code
                [ $? -eq 0 ] || return $ERR_SNAP

                ciop-log "INFO" "Scaling and alpha band addition to "$mission" image: $img"
                #extract min max to avoid full white image issue
                tiffProduct=temp-outputfile2.tif
                sourceBandName=band_1
                min_max=$( extract_min_max $tiffProduct $sourceBandName )
                [ $? -eq 0 ] || return ${ERR_CONVERT}
                # since min_max is like "minValue" "maxValue" these space separated strings can be directly given to gdal_translate
                gdal_translate -scale ${min_max} -ot Byte -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "ALPHA=YES" temp-outputfile2.tif temp-outputfile3.tif
                returnCode=$?
                [ $returnCode -eq 0 ] || return ${ERR_CONVERT}

                gdalwarp -ot Byte -srcnodata 0 -dstnodata 0 -dstalpha -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "ALPHA=YES" -t_srs EPSG:3857 temp-outputfile3.tif ${OUTPUTDIR}/${img}
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

  if [[ "${mission}" == "Resurs-P" ]]; then
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

  if [[ "${mission}" == "Radarsat-2" ]]; then
      if [[ -d "${retrievedProduct}" ]]; then
          product_xml=$(find ${retrievedProduct}/ -name 'product.xml')
          ciop-log "DEBUG" "product_xml ${product_xml}"
          #get band co-pol from product name
          bandCoPol=""
          if [[ $( echo ${productName} | grep "HH" ) != "" ]] ; then
              bandCoPol="Sigma0_HH"
          elif [[ $( echo ${productName} | grep "VV" ) != "" ]]; then
              bandCoPol="Sigma0_VV"
          else
              return ${ERR_WRONGPOLARIZATION}
          fi
          # get pixel spacing from product_xml
          pixelSpacing=$( cat ${product_xml} | grep sampledPixelSpacing | sed -n -e 's|^.*<sampledPixelSpacing .*>\(.*\)</sampledPixelSpacing>|\1|p' )
          ml=1
          outProd=${TMPDIR}/rs2_cal_tc_db_co_pol
          outProdTIF=${outProd}.tif
          # prepare the SNAP request
          SNAP_REQUEST=$( create_snap_request_cal_ml_tc_db "${product_xml}" "${bandCoPol}" "${ml}" "${pixelSpacing}" "${outProd}" )
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
          sourceBandName=${bandCoPol}_db
          #min max percentiles to be used in histogram stretching
          pc_min=2
          pc_max=95
          pc_min_max=$( extract_pc1_pc2 $outProdTIF $sourceBandName $pc_min $pc_max )
          [ $? -eq 0 ] || return ${ERR_CONVERT}
          # extract coefficient for linear stretching
          min_out=1
          max_out=255
          $_CIOP_APPLICATION_PATH/data_download_publish/linearEquationCoefficients.py ${pc_min_max} ${min_out} ${max_out} > ab.txt
          a=$( cat ab.txt | grep a | sed -n -e 's|^.*a=\(.*\)|\1|p')
          b=$( cat ab.txt | grep b |  sed -n -e 's|^.*b=\(.*\)|\1|p')
          ciop-log "INFO" "Linear stretching of dB values "$mission" image: $img"
          SNAP_REQUEST=$( create_snap_request_linear_stretching "${outProdTIF}" "${sourceBandName}" "${a}" "${b}" "${min_out}" "${max_out}" "temp-outputfile.tif" )
          [ $? -eq 0 ] || return ${SNAP_REQUEST_ERROR}
          [ $DEBUG -eq 1 ] && cat ${SNAP_REQUEST}
          # invoke the ESA SNAP toolbox
          gpt ${SNAP_REQUEST} -c "${CACHE_SIZE}" &> /dev/null
          # check the exit code
          [ $? -eq 0 ] || return $ERR_SNAP
          rm ${outProdTIF}
          ciop-log "INFO" "Reprojecting and alpha band addition to "$mission" image: $productName"
          gdalwarp -ot Byte -srcnodata 0 -dstnodata 0 -dstalpha -co "TILED=YES" -co "BLOCKXSIZE=512" -co "BLOCKYSIZE=512" -co "ALPHA=YES" -t_srs EPSG:3857 temp-outputfile.tif ${OUTPUTDIR}/${productName}.tif
          returnCode=$?
          [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
          #add overlay
          gdaladdo -r average ${OUTPUTDIR}/${productName}.tif 2 4 8 16
          returnCode=$?
          [ $returnCode -eq 0 ] || return ${ERR_CONVERT}
          # cleanup
          rm -f temp-outputfile.tif
      else
          ciop-log "ERROR" "The retrieved product ${retrievedProduct} is not a directory or does not exist"
          return ${ERR_UNPACKING}
      fi
  fi

  return 0

}


function create_snap_request_cal_ml_tc_db(){

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
      <sourceBands>${bandCoPol}</sourceBands>
    </parameters>
  </node>
  <node id="Write">
    <operator>Write</operator>
    <sources>
      <sourceProduct refid="LinearToFromdB"/>
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
statsFile=${TMPDIR}/displacement.stats
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
if [ "$inputNum" -ne "4" ] ; then
    return ${ERR_METADATA}
fi
# init variables
local outdir=$1
local mission=$2
local prodType=$3
local ref=$4
#get product date from input catalogue reference
startdate="$( opensearch-client -f atom "${ref}" startdate)"
# check error in query: put empty date in case of errors
res=$?
[ $res -eq 0 ] || startdate=""
#get name of tif product to be published
out_prod=$(ls ${outdir})
out_prod=$(basename ${out_prod})
out_prod_noext="${out_prod%%.*}"
out_properties=${outdir}/${out_prod_noext}.properties
# write properties file
cat << EOF > ${out_properties}
Service\ Name=Full Resolution Rasterization
Product\ Name=${out_prod}
Mission=${mission}
Product\ Type=${prodType}
Acquisition\ Date=${startdate}
EOF
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
        # report activity in the log
        # NOTE: it is assumed that the "generate_full_res_tif" function always provides results in $OUTPUTDIR
        # report activity in the log
	ciop-log "INFO" "Adding metadata for ${prodname}"
        add_metadata ${OUTPUTDIR} ${mission} ${prodType} ${currentProduct}
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

