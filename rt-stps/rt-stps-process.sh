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

#!/bin/bash


export PYTHONUNBUFFERED=TRUE
export SatelliteName=$1
export SOFTWARE_BUCKET=$2
export DATA_BUCKET=$3
export MIN_RAW_FILESIZE=2000000
# Get IMDSv2 token for local metadata
TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
export REGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s 169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/.$//')
export INSTANCE=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/instance-id)
export NOSHUTDOWN=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$INSTANCE" "Name=key,Values=NoShutdown" --region=$REGION --output=text| cut -f5)
export LC_SatelliteName=$(echo $SatelliteName | tr "[:upper:]" "[:lower:]")

# Init some vars
ERROR=""
NUM_UPLOADED_RAW_FILES=0
NUM_UPLOADED_L0_FILES=0
TIMESTR=$(date '+%Y%m%d-%H%M')
#export TIMESTR="20210308-1047"



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
  \"Errors\" : \"$ERROR\",
  \"LogFileName\" : \"${TIMESTR}-${SatelliteName}-data-capture.log\"
}"
    # Send SNS and quit
    #[ "${SNS_TOPIC}" != "" ] && sendSNS ${SNS_TOPIC} "S3 Bucket  : ${S3_BUCKET} ${NL} Satellite  : ${SatelliteName} ${NL} $(basename $0) Failed. Errors: $ERROR"
    [ "${SNS_TOPIC}" != "" ] && sendSNS ${SNS_TOPIC} "$MESSAGE"

    # Upload logfile e.g. data-capture_20200225-1844.log
    echo "Uploading /opt/aws/groundstation/bin/data-capture_${TIMESTR}.log to s3://${DATA_BUCKET}/data/${SatelliteName}/logs/${TIMESTR}-${SatelliteName}-data-capture.log"
    aws s3 cp /opt/aws/groundstation/bin/data-capture_${TIMESTR}.log s3://${DATA_BUCKET}/data/${SatelliteName}/logs/${TIMESTR}-${SatelliteName}-data-capture.log --region $REGION

    # Shutdown
    if [ "$NOSHUTDOWN" != "" ]; then
      echo "NoShutdown Tag detected, skipping shutdown"
      exit
    else
      echo "Finished (With errors). Shutting down. To prevent auto-shutdown for troubleshooting, create a new tag on this EC2 instance with a Key of NoShutdown and any non-empty value."
      shutdown -h now
    fi

  fi

}

# ========================================
#
# Main code section
#
# ========================================

export NOW=$(date '+%Y%m%d-%H:%M:%S')
START_TIME=$NOW
echo "$NOW	Satellite: ${SatelliteName}"
echo "$NOW	Software bucket: ${SOFTWARE_BUCKET}"
echo "$NOW	Software bucket: ${DATA_BUCKET}"
# Add Additional Variable Display
echo "$NOW	Region: ${REGION}"
echo "$NOW	Instance ID: ${INSTANCE}"
echo "$NOW	NoShutdown: ${NOSHUTDOWN}"

# If SNS topic is configured
if [ -f /opt/aws/groundstation/bin/getSNSTopic.sh ] ; then
  source /opt/aws/groundstation/bin/getSNSTopic.sh
  echo "$NOW	Using SNS Topic: ${SNS_TOPIC}"
fi

#	=============================
#	RT-STPS Install (if needed)
#	=============================

#	Check if RT-STPS is installed already
if [ -d "/root/rt-stps" ]; then
	export NOW=$(date '+%Y%m%d-%H:%M:%S')
	echo "$NOW	RT-STPS already installed, skipping installation"
else
	export NOW=$(date '+%Y%m%d-%H:%M:%S')
	echo "$NOW	Getting RT-STPS software from S3 software bucket: ${SOFTWARE_BUCKET}"
	cd ~
	
  # New RT-STPS V7 file
  aws s3 cp s3://space-solutions-eu-west-1/software/RT-STPS/RT-STPS_7.0.tar.gz . --region eu-west-1 || handleError "Error code ${?}. Failed to get RT-STPS_7.0.tar.gz from s3://space-solutions-eu-west-1/software/RT-STPS/" "FATAL"
  aws s3 cp s3://space-solutions-eu-west-1/software/RT-STPS/RT-STPS_7.0_PATCH_1.tar.gz . --region eu-west-1 || handleError "Error code ${?}. Failed to get RT-STPS_7.0.tar.gz from s3://space-solutions-eu-west-1/software/RT-STPS/" "FATAL"

	export NOW=$(date '+%Y%m%d-%H:%M:%S')
	echo "$NOW	Installing RT-STPS..."
	cd ~
	# Extract main package
  tar xzf RT-STPS_7.0.tar.gz

	# Install
	cd rt-stps
	./install.sh
	 cd ~
  ./rt-stps/jsw/bin/rt-stps-server.sh stop
  tar xzf RT-STPS_7.0_PATCH_1.tar.gz
fi



#	==================================
#	Fetch BIN file from S3 and combine
#	==================================

# read EC2 tags for path and contact_ID
export KEY_PREFIX=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$INSTANCE" "Name=key,Values=key-prefix" --region=${REGION} --output=text |cut -f5)

export PATH_TODAY=$(echo $KEY_PREFIX | cut -d '/' -f1-5)

export CONTACT_ID=$(echo $KEY_PREFIX | cut -d '/' -f6)

echo "Getting new files from S3"
S3_DOWNLOAD_START=$(date '+%Y%m%d-%H:%M:%S')
export SOURCE="s3://${DATA_BUCKET}/${PATH_TODAY}/"
export DEST="/root"

aws s3 sync $SOURCE $DEST --no-progress --region $REGION --exclude "*" \
--include "${CONTACT_ID}*.bin" || handleError "Error code ${?}. Failed to run aws s3 sync $SOURCE $DEST --region $REGION" "FATAL"

cd ~
# merging like this works because of the fixed file naming convention 
cat ${CONTACT_ID}*.bin > ${TIMESTR}-${SatelliteName}-raw.bin



#	Check size of raw file
if [ -e "${TIMESTR}-${SatelliteName}-raw.bin" ]; then
	FILESIZE=$(stat -c%s "${TIMESTR}-${SatelliteName}-raw.bin")
	export NOW=$(date '+%Y%m%d-%H:%M:%S')
	echo "$NOW Raw data size: $FILESIZE Bytes"
else
  handleError "Error code ${?}. File not found: ${TIMESTR}-${SatelliteName}-raw.bin" "FATAL"
fi



#	=============================
#	RT-STPS Processing
#	=============================

#	Only process if filesize is over 2MB
#	This skips processing if something went wrong

if (( $FILESIZE<$MIN_RAW_FILESIZE )); then
	#echo "$NOW Raw file less than $MIN_RAW_FILESIZE Bytes. Skipping further processing"
  #ERROR="Raw file less than $MIN_RAW_FILESIZE Bytes. Skipping further processing"
  handleError "Raw file less than $MIN_RAW_FILESIZE Bytes. Skipping further processing" "FATAL"
else
	#	Generate leapsec file name
	export TODAY=$(date '+%Y%m%d')
	#export TODAY=`echo $RAW_FILE| cut -f1 -d"-"`

	export LEAPSEC_FILE=leapsec.${TODAY}00.dat

	export NOW=$(date '+%Y%m%d-%H:%M:%S')

  if [ -e ~/rt-stps/${LEAPSEC_FILE} ] ; then
    echo "$NOW	Found required leapsec file: ~/rt-stps/${LEAPSEC_FILE}"
  else
    echo "$NOW	~/rt-stps/${LEAPSEC_FILE} not found. Getting latest leapsec file (${LEAPSEC_FILE}) from nasa.gov"
  	cd ~/rt-stps
  	curl ftp://is.sci.gsfc.nasa.gov/ancillary/temporal/${LEAPSEC_FILE} -o ${LEAPSEC_FILE} || handleError "Error code ${?}. Failed to get leapsec file from ftp://is.sci.gsfc.nasa.gov/ancillary/temporal/${LEAPSEC_FILE}" "WARNING"
  fi

	export NOW=$(date '+%Y%m%d-%H:%M:%S')
	echo "$NOW	Starting RT-STPS..."

	export CONFIG_FILE=~/rt-stps/config/${LC_SatelliteName}.xml
	export INPUT_FILE=~/${TIMESTR}-${SatelliteName}-raw.bin

	cd ~/rt-stps

	# Delete previous data
	rm -rf ~/data/*

	# Start RT-STPS server
  RTSTPS_START=$(date '+%Y%m%d-%H:%M:%S')
	./jsw/bin/rt-stps-server.sh start || handleError "Error code ${?}. Failed start RT-STPS server" "FATAL"

	# Process the raw data using RT-STPS batch mode
	./bin/batch.sh $CONFIG_FILE $INPUT_FILE || handleError "Error code ${?}. Failed to run RT-STPS batch mode" "FATAL"

	# Stop the server
	./jsw/bin/rt-stps-server.sh stop || handleError "Error code ${?}. Failed stop RT-STPS server" "WARNING"
  RTSTPS_END=$(date '+%Y%m%d-%H:%M:%S')

  # Check for new level 0 files
  NUM_NEW_L0_FILES=0
  NUM_NEW_L0_FILES=$(ls -l ~/data/ | grep -v ^total | wc -l)
  echo "${NUM_NEW_L0_FILES} new Level 0 files created by RT-STPS"

  # Skip S3 upload if no new files
  if [ $NUM_NEW_L0_FILES == 0 ] ; then
    handleError "No new files found in ~/data/ Skipping S3 upload" "FATAL"
  fi

#	=============================
#	S3 Upload
#	=============================

  S3_UPLOAD_START=$(date '+%Y%m%d-%H:%M:%S')
	echo "$NOW	Uploading raw data to S3"
  NUM_RAW_FILES_BEFORE_UPLOAD=$(aws s3 ls s3://${DATA_BUCKET}/data/${SatelliteName}/raw/ --region $REGION | grep -v ^total | wc -l)
	aws s3 cp ~/${TIMESTR}-${SatelliteName}-raw.bin s3://${DATA_BUCKET}/data/${SatelliteName}/raw/${TIMESTR}-${SatelliteName}-raw.bin --no-progress --region $REGION || handleError "Error code ${?}. Failed to call aws s3 cp ~/${TIMESTR}-${SatelliteName}-raw.bin s3://${DATA_BUCKET}/data/${SatelliteName}/raw/${TIMESTR}-${SatelliteName}-raw.bin --region $REGION" "FATAL"
  NUM_RAW_FILES_AFTER_UPLOAD=$(aws s3 ls s3://${DATA_BUCKET}/data/${SatelliteName}/raw/ --region $REGION | grep -v ^total | wc -l)

  let NUM_UPLOADED_RAW_FILES=$NUM_RAW_FILES_AFTER_UPLOAD-$NUM_RAW_FILES_BEFORE_UPLOAD

  if [ $NUM_UPLOADED_RAW_FILES == 0 ] ; then
    handleError "No new raw file uploaded to S3." "WARNING"
  fi

	export NOW=$(date '+%Y%m%d-%H:%M:%S')
	echo "$NOW	Uploading level 0 data to S3"
  NUM_L0_FILES_BEFORE_UPLOAD=$(aws s3 ls s3://${DATA_BUCKET}/data/${SatelliteName}/level0/ --region $REGION | grep -v ^total | wc -l)
	aws s3 sync ~/data/ s3://${DATA_BUCKET}/data/${SatelliteName}/level0/ --no-progress --region $REGION || handleError "Error code ${?}. aws s3 sync ~/data/ s3://${DATA_BUCKET}/data/${SatelliteName}/level0/ --region $REGION" "FATAL"
  NUM_L0_FILES_AFTER_UPLOAD=$(aws s3 ls s3://${DATA_BUCKET}/data/${SatelliteName}/level0/ --region $REGION | grep -v ^total | wc -l)
  S3_UPLOAD_END=$(date '+%Y%m%d-%H:%M:%S')

  let NUM_UPLOADED_L0_FILES=$NUM_L0_FILES_AFTER_UPLOAD-$NUM_L0_FILES_BEFORE_UPLOAD

  if [ $NUM_UPLOADED_L0_FILES == 0 ] ; then
    handleError "No new L0 files uploaded to S3." "WARNING"
  fi

fi

#	=============================
#	Send SNS Notification
#	=============================

if [ -f /opt/aws/groundstation/bin/getSNSTopic.sh ] ; then

MESSAGE="{
  \"Result\" : \"Success\",
  \"Errors\" : \"$ERROR\",
  \"DataBucket\" : \"${DATA_BUCKET}\",
  \"SoftwareBucket\" : \"${SOFTWARE_BUCKET}\",
  \"Satellite\" : \"${SatelliteName}\",
  \"StartTime\" : \"${START_TIME}\",
  \"RtStpsStartTime\" : \"${RTSTPS_START}\",
  \"RtStpsEndTime\" : \"${RTSTPS_END}\",
  \"S3UploadStartTime\" : \"${S3_UPLOAD_START}\",
  \"S3UploadEndTime\" : \"${S3_UPLOAD_END}\",
  \"NumUploadedRawFiles\" : \"${NUM_UPLOADED_RAW_FILES}\",
  \"NumUploadedL0Files\" : \"${NUM_UPLOADED_L0_FILES}\",
  \"BytesReceived\" : \"${FILESIZE}\",
  \"RawDataFileName\" : \"${TIMESTR}-${SatelliteName}-raw.bin\",
  \"LogFileName\" : \"${TIMESTR}-${SatelliteName}-data-capture.log\"
}"

sendSNS ${SNS_TOPIC} "$MESSAGE"

fi

# Upload logfile e.g. data-capture_20200225-1844.log
echo "Uploading /opt/aws/groundstation/bin/data-capture_${TIMESTR}.log to s3://${DATA_BUCKET}/data/${SatelliteName}/logs/${TIMESTR}-${SatelliteName}-data-capture.log"
aws s3 cp /opt/aws/groundstation/bin/data-capture_${TIMESTR}.log s3://${DATA_BUCKET}/data/${SatelliteName}/logs/${TIMESTR}-${SatelliteName}-data-capture.log --region $REGION || handleError "Error code ${?}. Failed to call aws s3 cp /opt/aws/groundstation/bin/data-capture_${TIMESTR}.log s3://${DATA_BUCKET}/data/${SatelliteName}/logs/data-capture_${TIMESTR}.log --region $REGION" "WARNING"

# Shutdown
#echo "Finished. Shutting down"
#shutdown -h now

if [ "$NOSHUTDOWN" != "" ]; then
   echo "NoShutdown Tag detected, skipping shutdown"
else
   echo "Finished. Shutting down"
   shutdown -h now
fi






