import numpy as np
import gdal, gdalconst
import os

# See http://www.gdal.org/classVRTRasterBand.html#a155a54960c422941d3d5c2853c6c7cef
def linear_strecth(inFname, bandIndex, valMin, valMax, outFname):
  """
  Given a filename and limit values, creates an 8-bit GeoTIFF with linear  
  strething between limit values and keeping 0 as nodata value.
  """
  src = gdal.Open(inFname)
  band = src.GetRasterBand(int(bandIndex))
  minVal = float(valMin)
  maxVal = float(valMax)
  
  # gdal_calc to clip values lower than min
  # Print out and execute gdal_calc command
  gdalCalcCommand="gdal_calc.py -A "+inFname+" --A_band="+bandIndex+" --calc="+'"'+str(minVal)+"*logical_and(A>0, A<="+str(minVal)+")+A*(A>"+str(minVal)+")"+'"'+" --outfile=gdal_calc_result.tif --NoDataValue=0"
  print "running  "+gdalCalcCommand
  os.system(gdalCalcCommand)
  
  #gdal_translate to make linear strecthing bewtween 1 and 255 (to keep 0 fro no_data)
  # Print out and execute gdal_translate command 
  gdalTranslateCommand="gdal_translate -b 1 -co TILED=YES -co BLOCKXSIZE=512 -co BLOCKYSIZE=512 -co ALPHA=YES -ot Byte -a_nodata 0 -scale "+str(minVal)+" "+str(maxVal)+" 1 255 gdal_calc_result.tif "+outFname 
  print "running  "+gdalTranslateCommand
  os.system(gdalTranslateCommand)
  
  # remove temp file
  os.system("rm gdal_calc_result.tif")
  
  return 0


# Invoke as: `python hist_skip.py my-raster.tif`.
if __name__ == '__main__':
  import sys

  if len(sys.argv) == 6:
    linear_strecth(sys.argv[1],sys.argv[2],sys.argv[3],sys.argv[4],sys.argv[5])
  else:
    print "python linear_strecth INPUT-RASTER BAND-INDEX MIN-VAL MAX-VAL OUTPUT-RASTER"
