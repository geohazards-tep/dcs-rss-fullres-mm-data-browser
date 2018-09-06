import numpy as np
import gdal, gdalconst
import os

# See http://www.gdal.org/classVRTRasterBand.html#a155a54960c422941d3d5c2853c6c7cef
def hist_skip(inFname, bandIndex, percentileMin, percentileMax, outFname, nbuckets=1000):
  """
  Given a filename, finds approximate percentile values and provides the
  gdal_translate invocation required to create an 8-bit PNG.
  Works by evaluating a histogram of the original raster with a large number of
  buckets between the raster minimum and maximum, then estimating the
  probability mass and distribution functions before reporting the percentiles
  requested.
  N.B. This technique is very approximate and hasn't been checked for asymptotic
  convergence. Heck, it uses GDAL's `GetHistogram` function in approximate mode,
  so you're getting approximate percentiles using an approximated histogram.
  Optional arguments:
  - `percentiles`: list of percentiles, between 0 and 100 (inclusive).
  - `nbuckets`: the more buckets, the better percentile approximations you get.
  """
  src = gdal.Open(inFname)
  band = src.GetRasterBand(int(bandIndex))
  percentiles = [ float(percentileMin), float(percentileMax) ]
  # Use GDAL to find the min and max
  (lo, hi, avg, std) = band.GetStatistics(True, True)

  # Use GDAL to calculate a big histogram
  rawhist = band.GetHistogram(min=lo, max=hi, buckets=nbuckets)
  binEdges = np.linspace(lo, hi, nbuckets+1)

  # Probability mass function. Trapezoidal-integration of this should yield 1.0.
  pmf = rawhist / (np.sum(rawhist) * np.diff(binEdges[:2]))
  # Cumulative probability distribution. Starts at 0, ends at 1.0.
  distribution = np.cumsum(pmf) * np.diff(binEdges[:2])

  # Which histogram buckets are close to the percentiles requested?
  idxs = [np.sum(distribution < p / 100.0) for p in percentiles]
  # These:
  vals = [binEdges[i] for i in idxs]

  # Append 0 and 100% percentiles (min & max)
  percentiles = [0] + percentiles + [100]
  vals = [lo] + vals + [hi]

  # Print the percentile table
  print "percentile (out of 100%),value at percentile"
  for (p, v) in zip(percentiles, vals):
    print "%f,%f" % (p, v)
 
  if vals[1] == 0:
    print "percentile "+str(percentileMin)+" is equal to 0" 
    print "Percentile recomputation as pNoZero+"+str(percentileMin)+", where pNoZero is the first percentile with no zero value"

    pNoZero=0
    for p in range(int(percentileMin),100):
      idx = np.sum(distribution < float(p) / 100.0)
      val = binEdges[idx]
      if val > 0:
        pNoZero=p+int(percentileMin)
        break
    percentiles = [ float(pNoZero), float(percentileMax) ]
    # Which histogram buckets are close to the percentiles requested?
    idxs = [np.sum(distribution < p / 100.0) for p in percentiles]
    # These:
    vals = [binEdges[i] for i in idxs]

    # Append 0 and 100% percentiles (min & max)
    percentiles = [0] + percentiles + [100]
    vals = [lo] + vals + [hi]
    # Print the percentile table
    print "percentile (out of 100%),value at percentile"
    for (p, v) in zip(percentiles, vals):
      print "%f,%f" % (p, v)
  
  # Print out gdal_calc command
  gdalCalcCommand="gdal_calc.py -A "+inFname+" --A_band="+bandIndex+" --calc="+'"'+str(vals[1])+"*logical_and(A>0, A<="+str(vals[1])+")+A*(A>"+str(vals[1])+")"+'"'+" --outfile=gdal_calc_result.tif --NoDataValue=0"
  print "running  "+gdalCalcCommand
  os.system(gdalCalcCommand)
  
  # Print out gdal_translate command (what we came here for anyway)
  gdalTranslateCommand="gdal_translate -b 1 -co TILED=YES -co BLOCKXSIZE=512 -co BLOCKYSIZE=512 -co ALPHA=YES -ot Byte -a_nodata 0 -scale "+str(vals[1])+" "+str(vals[2])+" 1 255 gdal_calc_result.tif "+outFname 
  print "running  "+gdalTranslateCommand
  os.system(gdalTranslateCommand)
  
  # remove temp file
  os.system("rm gdal_calc_result.tif")
  
  return (vals, percentiles)


# Invoke as: `python hist_skip.py my-raster.tif`.
if __name__ == '__main__':
  import sys

  if len(sys.argv) == 6:
    hist_skip(sys.argv[1],sys.argv[2],sys.argv[3],sys.argv[4],sys.argv[5])
  else:
    print "python hist_skip.py INPUT-RASTER BAND-INDEX PERCENTILE-MIN PERCENTILE-MAX OUTPUT-RASTER"
