# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

# Permission is hereby granted, free of charge, to any person obtaining a copy of this
# software and associated documentation files (the "Software"), to deal in the Software
# without restriction, including without limitation the rights to use, copy, modify,
# merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
# INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
# PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
# HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# This package depends on and may incorporate or retrieve a number of third-party
# software packages (such as open source packages) at install-time or build-time
# or run-time ("External Dependencies"). The External Dependencies are subject to
# license terms that you must accept in order to use this package. If you do not
# accept all of the applicable license terms, you should not use this package. We
# recommend that you consult your company’s open source approval policy before
# proceeding.

# Provided below is a list of External Dependencies and the applicable license
# identification as indicated by the documentation associated with the External
# Dependencies as of Amazon's most recent review.

# THIS INFORMATION IS PROVIDED FOR CONVENIENCE ONLY. AMAZON DOES NOT PROMISE THAT
# THE LIST OR THE APPLICABLE TERMS AND CONDITIONS ARE COMPLETE, ACCURATE, OR
# UP-TO-DATE, AND AMAZON WILL HAVE NO LIABILITY FOR ANY INACCURACIES. YOU SHOULD
# CONSULT THE DOWNLOAD SITES FOR THE EXTERNAL DEPENDENCIES FOR THE MOST COMPLETE
# AND UP-TO-DATE LICENSING INFORMATION.

# YOUR USE OF THE EXTERNAL DEPENDENCIES IS AT YOUR SOLE RISK. IN NO EVENT WILL
# AMAZON BE LIABLE FOR ANY DAMAGES, INCLUDING WITHOUT LIMITATION ANY DIRECT,
# INDIRECT, CONSEQUENTIAL, SPECIAL, INCIDENTAL, OR PUNITIVE DAMAGES (INCLUDING
# FOR ANY LOSS OF GOODWILL, BUSINESS INTERRUPTION, LOST PROFITS OR DATA, OR
# COMPUTER FAILURE OR MALFUNCTION) ARISING FROM OR RELATING TO THE EXTERNAL
# DEPENDENCIES, HOWEVER CAUSED AND REGARDLESS OF THE THEORY OF LIABILITY, EVEN
# IF AMAZON HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES. THESE LIMITATIONS
# AND DISCLAIMERS APPLY EXCEPT TO THE EXTENT PROHIBITED BY APPLICABLE LAW.

# IPOPP and RT-STPS (https://directreadout.sci.gsfc.nasa.gov) - NASA Open Source Agreement 1.3 (https://ti.arc.nasa.gov/opensource/nosa)


# This script automates the processing of level 0 Raw Data Record (RDR) files from JPSS1 
# into level 1 and level 2 products. The level 0 files must be produced by 
# Real-time Software Telemetry Processing System (RT-STPS). The files are ingested into
# International Planetary Observation Processing Package (IPOPP) for processing.
# The script ingests files for the VIIRS, ATMS and CrIS instruments onboard the craft.  


#!/bin/bash
# Run as the ipopp user

SatelliteName=$1
SOFTWARE_BUCKET=$2
DATA_BUCKET=$3
REGION=$(curl -s 169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/.$//')
LC_SatelliteName=$(echo $SatelliteName | tr "[:upper:]" "[:lower:]")
TIMESTR=$(date '+%Y%m%d-%H%M')

# Determines if a thumbnail should be created
# If created it is shared in the SNS notification as a public url or presigned url
# Valid options: 'disabled', 'public', 'presign'
THUMBNAIL_OPTION="disabled"

# ========================================
# Functions
# ========================================

function sendSNS {

  SNS_TOPIC=$1
  MESSAGE=$2
  echo "Sending SNS Message."
  echo "Topic Arn: ${SNS_TOPIC}"
  echo "Message: ${MESSAGE}"
  aws sns publish --topic-arn ${SNS_TOPIC} --message "$MESSAGE" --region $REGION

}

function handleError {

  # If ERROR is not blank concatenate with previous error
  [ "$ERROR" == "" ] && ERROR="${2}:${1}" || ERROR="$ERROR ; ${2}:${1}"

  # sendSNS if SNS_TOPIC is not blank
  if [ "$2" == "FATAL" ]; then
    echo "Fatal Error: $1"

MESSAGE="{
  \"Result\" : \"Failed\",
  \"DataBucket\" : \"${DATA_BUCKET}\",
  \"SoftwareBucket\" : \"${SOFTWARE_BUCKET}\",
  \"Satellite\" : \"${SatelliteName}\",
  \"Errors\" : \"$ERROR\"
}"
    # Send SNS and quit
    #[ "${SNS_TOPIC}" != "" ] && sendSNS ${SNS_TOPIC} "S3 Bucket  : ${DATA_BUCKET} ${NL} Satellite  : ${SatelliteName} ${NL} $(basename $0) Failed. Errors: $ERROR"
    [ "${SNS_TOPIC}" != "" ] && sendSNS ${SNS_TOPIC} "$MESSAGE"
    exit 1
  fi

}

# ========================================
#
# Main code section
#
# ========================================

START_TIME=$(date '+%Y%m%d-%H:%M:%S')

# Stop IPOPP if running
#echo "Stopping IPOPP if running"
#/home/ipopp/drl/tools/services.sh stop

# If SNS topic is configured
if [ -f /opt/aws/groundstation/bin/getSNSTopic.sh ] ; then
  source /opt/aws/groundstation/bin/getSNSTopic.sh
  echo "Using SNS Topic: ${SNS_TOPIC}"
fi

# AQUA/MODIS Dirs:
# /home/ipopp/drl/data/pub/gsfcdata/${LC_SatelliteName}/modis/level0,1,2
# /home/ipopp/drl/data/pub/gsfcdata/${LC_SatelliteName}/gbad

# JPSS1/VIIRS Dirs:
# /home/ipopp/drl/data/pub/gsfcdata/jpss1/viirs/level0,1,2
# /home/ipopp/drl/data/pub/gsfcdata/jpss1/spacecraft/level0

# JPSS1/VIIRS Timings:
# VIIRS-L1: 21 mins!!
# L1-SDR: 2m 53s
# H2G vtoatcolour: 17s
# H2G vml2h5.getiff:

# VIRRS_C-SDR: 23m 12s
# CVIIRS: 1m 22s
# BlueMarble viirs-ctcolor*: 28s
# BlueMarble viirs-tcolor: 3m 38s


 if [ "$SatelliteName"=="JPSS1" ]; then

   #BASE_DIR="/home/ipopp/drl/data/pub/gsfcdata/${LC_SatelliteName}/viirs"
   #OTHER_DIR="/home/ipopp/drl/data/pub/gsfcdata/${LC_SatelliteName}/spacecraft/level0"
    INSTRUMENT="viirs"

 fi

NUM_L0_FILES_BEFORE_INGEST=$(ls -l /home/ipopp/drl/data/pub/gsfcdata/${LC_SatelliteName}/${INSTRUMENT}/level0 | grep -v ^total | wc -l)
NUM_L1_FILES_BEFORE_INGEST=$(ls -l /home/ipopp/drl/data/pub/gsfcdata/${LC_SatelliteName}/${INSTRUMENT}/level1 | grep -v ^total | wc -l)
NUM_L2_FILES_BEFORE_INGEST=$(ls -l /home/ipopp/drl/data/pub/gsfcdata/${LC_SatelliteName}/${INSTRUMENT}/level2 | grep -v ^total | wc -l)

echo "NUM_L0_FILES_BEFORE_INGEST: $NUM_L0_FILES_BEFORE_INGEST"
echo "NUM_L1_FILES_BEFORE_INGEST: $NUM_L1_FILES_BEFORE_INGEST"
echo "NUM_L2_FILES_BEFORE_INGEST: $NUM_L2_FILES_BEFORE_INGEST"


echo "Getting new files from S3"
S3_DOWNLOAD_START=$(date '+%Y%m%d-%H:%M:%S')
export SOURCE="s3://${DATA_BUCKET}/data/${SatelliteName}/level0/"
export DEST="/home/ipopp/drl/data/dsm/ingest"

# Include the following Product Data Set (PDS) and Raw Data Record (RDR) files:
# Although RT-STPS may produce more PDS, RDR files, IPOPP can only currently process these.
#           Files                 | File type |    Sensor        |  SPA Service on IPOPP Dashboard 
# P15*0000*, P15*0008*, P15*0011* |    PDS    |  SNPP+JPSS S/C   |  VIIRS-L1
# P15*0826VIIRSSCIENCE*           |    PDS    |  SNMP+JPSS VIIRS |  VIIRS-L1
# RNSCA-RVIRS_*                   |    RDR    |  SNMP+JPSS VIIRS |  VIIRS_C-SDR
# RATMS-RNSCA_*                   |    RDR    |  SNMP+JPSS ATMS  |  ATMS_C-SDR
# RCRIS-RNSCA_*                   |    RDR    |  SNMP+JPSS CrIS  |  CRIS_C-SDR
# Processing can be done with either PDS or RDR files, but not both simultenously, as per IPOPP user guide. 
# VIIRS produces BlueMarble level2 .tif Earth images. It takes either 2 PDS files or 1 RDR file. 
# Ingesting RDR files produces the equivalent PDS files in /home/ipopp/drl/data/pub/gsfcdata/jpss1/viirs/level0

# sync all usable files 
aws s3 sync $SOURCE $DEST --no-progress --region $REGION --exclude "*" \
--include "P15*0000*" --include "P15*0008*" --include "P15*0011*" --include "P15*0826VIIRSSCIENCE*" --include "RNSCA-RVIRS_*" \
--include "RATMS-RNSCA_*" --include "RCRIS-RNSCA_*" || handleError "Error code ${?}. Failed to run aws s3 sync $SOURCE $DEST --region $REGION" "FATAL"

S3_DOWNLOAD_END=$(date '+%Y%m%d-%H:%M:%S')

# Test if we have access to the NASA site for ancillary files
echo "Testing access to ftp://is.sci.gsfc.nasa.gov"
curl --silent ftp://is.sci.gsfc.nasa.gov > /dev/null
EXIT_CODE=$?

if [ $EXIT_CODE != 0 ] ; then

  handleError "Error code $EXIT_CODE. Failed to connect to ftp://is.sci.gsfc.nasa.gov for IPOPP ancillary files" "WARNING"
  echo "No access to ftp://is.sci.gsfc.nasa.gov Getting IPOPP ancillary files from S3"

  TODAY=$(date '+%Y%m%d')
  LEAPSEC_FILE=leapsec.${TODAY}00.dat
  LEAPSEC_FILE_PATH=/home/ipopp/drl/data/pub/ancillary/temporal/${LEAPSEC_FILE}

  SOURCE="s3://${SOFTWARE_BUCKET}/software/IPOPP/ancillary-data/"
  DEST="/home/ipopp/drl/data/pub/CompressedArchivedAncillary/"
  aws s3 sync ${SOURCE} ${DEST} --no-progress --region $REGION || handleError "Error code ${?}. Failed to run aws s3 sync ${SOURCE} ${DEST} --region $REGION" "WARNING"
  #  Update permissions to avoid rm delete confirmation prompts from IPOPP ancillary download script
  chmod -R 777 /home/ipopp/drl/data/pub/CompressedArchivedAncillary

else

  echo "Connection to ftp://is.sci.gsfc.nasa.gov OK"

fi

# Start IPOPP services
IPOPP_INGEST_START=$(date '+%Y%m%d-%H:%M:%S')
echo "Starting IPOPP services"
/home/ipopp/drl/tools/services.sh start || handleError "Error code ${?}. Failed to start IPOPP services" "FATAL"

# Start IPOPP ingest
echo "Ingesting files into IPOPP"
/home/ipopp/drl/tools/ingest_ipopp.sh || handleError "Error code ${?}. Failed to run IPOPP ingest" "FATAL"
IPOPP_INGEST_END=$(date '+%Y%m%d-%H:%M:%S')

# Sleep to allow IPOPP to process some files
echo "Sleeping for 80 minutes to wait for IPOPP to create files"
sleep 4800

# The IPOPP ingest tasks copies file from and to the locations below
# Therefore we can remove all files in the S3 bucket that exist in the 'to' dir
# This avoids them being processed again during the next ingest
# from: /home/ipopp/drl/data/dsm/ingest
# to: /home/ipopp/drl/data/pub/gsfcdata/${LC_SatelliteName}/${INSTRUMENT}
echo "Removing ingested level 0 files from S3 bucket"
export LOCAL_DIR="/home/ipopp/drl/data/pub/gsfcdata/${LC_SatelliteName}/${INSTRUMENT}/level0"
export REMOTE_DIR="s3://${DATA_BUCKET}/data/${SatelliteName}/level0"

pushd $LOCAL_DIR
for H5_FILE in *.h5; do

    # Skip if not a file
    [ -f "$H5_FILE" ] || break

    echo "Found locally processed h5 file: $H5_FILE. Removing from S3 bucket if it exists"
    echo "aws s3 rm $REMOTE_DIR/$H5_FILE --region $REGION"
    aws s3 rm $REMOTE_DIR/$H5_FILE --region $REGION || handleError "Error code ${?}. Failed to run aws s3 rm $REMOTE_DIR/$H5_FILE --region $REGION" "WARNING"

done


for PDS_FILE in *.PDS; do

    # Skip if not a file
    [ -f "$PDS_FILE" ] || break

    echo "Found locally processed PDS file: $PDS_FILE. Removing from S3 bucket if it exists"
    echo "aws s3 rm $REMOTE_DIR/$PDS_FILE --region $REGION"
    aws s3 rm $REMOTE_DIR/$PDS_FILE --region $REGION || handleError "Error code ${?}. Failed to run aws s3 rm $REMOTE_DIR/$PDS_FILE --region $REGION" "WARNING"

done



# Start loop to push files to S3
SOURCE="/home/ipopp/drl/data/pub/gsfcdata/${LC_SatelliteName}/${INSTRUMENT}/"
DEST="s3://${DATA_BUCKET}/data/${SatelliteName}/${INSTRUMENT}/"
SLEEPTIME=400
x=1
MAX_ITERATIONS=3
NUM_NEW_L2_FILES_AFTER_SLEEP=0

while [ $x -le $MAX_ITERATIONS ]
do
    echo "Pushing ${INSTRUMENT} files to S3"
    aws s3 sync $SOURCE $DEST --no-progress --region $REGION || handleError "Error code ${?}. Failed to run aws s3 sync $SOURCE $DEST --region $REGION" "WARNING"

    echo "Getting num L2 files, before sleep"
    NUM_L2_FILES_BEFORE_SLEEP=$(ls -l /home/ipopp/drl/data/pub/gsfcdata/${LC_SatelliteName}/${INSTRUMENT}/level2 | grep -v ^total | wc -l)

    echo "[$x] Sleeping for $SLEEPTIME seconds"
    x=$(( $x + 1 ))
    sleep $SLEEPTIME

    echo "Getting num L2 files, after sleep"
    NUM_L2_FILES_AFTER_SLEEP=$(ls -l /home/ipopp/drl/data/pub/gsfcdata/${LC_SatelliteName}/${INSTRUMENT}/level2 | grep -v ^total | wc -l)
    let NUM_NEW_L2_FILES_AFTER_SLEEP=$NUM_L2_FILES_AFTER_SLEEP-$NUM_L2_FILES_BEFORE_SLEEP

    if [[ "$NUM_NEW_L2_FILES_AFTER_SLEEP" == '0' ]]; then
      echo "No new L2 files created after sleeping. Considering the processing finished."
      break
    fi

done
echo "Finished!"

NUM_L0_FILES_AFTER_INGEST=$(ls -l /home/ipopp/drl/data/pub/gsfcdata/${LC_SatelliteName}/${INSTRUMENT}/level0 | grep -v ^total | wc -l)
NUM_L1_FILES_AFTER_INGEST=$(ls -l /home/ipopp/drl/data/pub/gsfcdata/${LC_SatelliteName}/${INSTRUMENT}/level1 | grep -v ^total | wc -l)
NUM_L2_FILES_AFTER_INGEST=$(ls -l /home/ipopp/drl/data/pub/gsfcdata/${LC_SatelliteName}/${INSTRUMENT}/level2 | grep -v ^total | wc -l)


echo "NUM_L0_FILES_AFTER_INGEST: $NUM_L0_FILES_AFTER_INGEST"
echo "NUM_L1_FILES_AFTER_INGEST: $NUM_L1_FILES_AFTER_INGEST"
echo "NUM_L2_FILES_AFTER_INGEST: $NUM_L2_FILES_AFTER_INGEST"


let NUM_NEW_L0_FILES=$NUM_L0_FILES_AFTER_INGEST-$NUM_L0_FILES_BEFORE_INGEST
let NUM_NEW_L1_FILES=$NUM_L1_FILES_AFTER_INGEST-$NUM_L1_FILES_BEFORE_INGEST
let NUM_NEW_L2_FILES=$NUM_L2_FILES_AFTER_INGEST-$NUM_L2_FILES_BEFORE_INGEST


echo "New L0 Files : ${NUM_NEW_L0_FILES}"
echo "New L1 Files : ${NUM_NEW_L1_FILES}"
echo "New L2 Files : ${NUM_NEW_L2_FILES}"


#	=======================================================
#	Create thumbnail of the composite RGB SHARPTCOLOR image
#	=======================================================

if [ $THUMBNAIL_OPTION != 'disabled' ] ; then

  echo "Creating crefl thumbnail image"

  # Get the latest crefl image
  WORKING_DIR="/home/ipopp/drl/data/pub/gsfcdata/${LC_SatelliteName}/${INSTRUMENT}/level2"
  pushd ${WORKING_DIR}
  LATEST_SHARPT_IMAGE=$(ls -lt  *SHARPTCOLOR.tif | head -1 | awk '{print $9}')
 

  # Create a 200px high thumbnail image
  convert -thumbnail x200 ${LATEST_SHARPT_IMAGE} thumb.${LATEST_SHARPT_IMAGE}

  # Generate S3 path
  TARGET_S3_PATH="s3://${DATA_BUCKET}/data/${SatelliteName}/${INSTRUMENT}/level2/thumb.${LATEST_SHARPT_IMAGE}"

fi

if [ $THUMBNAIL_OPTION == 'presign' ] ; then

  echo "Uploading thumbnail crefl image and creating presigned url"

  # Upload as private and create presigned URL
  aws s3 cp ${WORKING_DIR}/thumb.${LATEST_SHARPT_IMAGE} ${TARGET_S3_PATH} --region $REGION
  THUMBNAIL_URL=$(aws s3 presign ${TARGET_S3_PATH} --expires-in 604800 --region $REGION)

elif [ $THUMBNAIL_OPTION == 'public' ] ; then

  echo "Uploading thumbnail crefl image as public-read"

  # Alternative to a pre-signed URL, upload with public-read access
  aws s3 cp ${WORKING_DIR}/thumb.${LATEST_SHARPT_IMAGE} ${TARGET_S3_PATH} --acl public-read --region $REGION
  THUMBNAIL_URL="https://${DATA_BUCKET}.s3.${REGION}.amazonaws.com/data/${SatelliteName}/${INSTRUMENT}/level2/thumb.${LATEST_SHARPT_IMAGE}"

fi

#	=============================
#	Send SNS Notification
#	=============================

if [ -f /opt/aws/groundstation/bin/getSNSTopic.sh ] ; then

# The following command assumes there is only one mounted volume
DISK_USED_PERCENT=$(df -h | grep "^/dev/root" | awk '{print $5}')

# Get number of IPOPP Errors
/home/ipopp/drl/nsls/bin/print-logs.sh -eventlevel e > /tmp/ipopp.errors
NUM_ERRORS=$(egrep '^ERROR' /tmp/ipopp.errors | wc -l)

MESSAGE="{
  \"Result\" : \"Success\",
  \"Errors\" : \"$ERROR\",
  \"NumIpoppErrors\" : \"${NUM_ERRORS}\",
  \"DataBucket\" : \"${DATA_BUCKET}\",
  \"SoftwareBucket\" : \"${SOFTWARE_BUCKET}\",
  \"Satellite\" : \"${SatelliteName}\",
  \"StartTime\" : \"${START_TIME}\",
  \"S3DownloadStartTime\" : \"${S3_DOWNLOAD_START}\",
  \"S3DownloadEndTime\" : \"${S3_DOWNLOAD_END}\",
  \"IpoppIngestStartTime\" : \"${IPOPP_INGEST_START}\",
  \"IpoppIngestEndTime\" : \"${IPOPP_INGEST_END}\",
  \"NumNewL0Files\" : \"${NUM_NEW_L0_FILES}\",
  \"NumNewL1Files\" : \"${NUM_NEW_L1_FILES}\",
  \"NumNewL2Files\" : \"${NUM_NEW_L2_FILES}\",
  \"LogFileName\" : \"${TIMESTR}-${SatelliteName}-ipopp-ingest.log\",
  \"DiskUsedPercent\" : \"${DISK_USED_PERCENT}\",
  \"ThumbnailUrl\" : \"${THUMBNAIL_URL}\"
}"

sendSNS ${SNS_TOPIC} "$MESSAGE"

fi

# Upload logfile to S3 /opt/aws/groundstation/bin/ipopp-ingest.log
echo "Uploading /opt/aws/groundstation/bin/ipopp-ingest.log to s3://${DATA_BUCKET}/data/${SatelliteName}/logs/${TIMESTR}-${SatelliteName}-ipopp-ingest.log"
aws s3 cp /opt/aws/groundstation/bin/ipopp-ingest.log s3://${DATA_BUCKET}/data/${SatelliteName}/logs/${TIMESTR}-${SatelliteName}-ipopp-ingest.log --region $REGION

echo "Stopping IPOPP services"
/home/ipopp/drl/tools/services.sh stop
