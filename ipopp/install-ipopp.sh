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


# Installs International Planetary Observation Processing Package (IPOPP) software on 
# the EC2 instance. The downloaded DRL-IPOPP_5.0.tar.gz must be present in /home/ipopp or
# in your software S3 bucket: s3://${SOFTWARE_BUCKET}/software/IPOPP/DRL-IPOPP_450.tar

#!/bin/bash

S3_BUCKET=$1
REGION=$2


if [ ! -e /home/ipopp/DRL-IPOPP_5.0.tar.gz ]; then

  echo "Downloading DRL-IPOPP_5.0.tar.gz from S3 Bucket: ${S3_BUCKET}"
  aws s3 cp s3://${S3_BUCKET}/software/IPOPP/DRL-IPOPP_5.0.tar.gz /home/ipopp/DRL-IPOPP_5.0.tar.gz --region $REGION
  
else
  echo "DRL-IPOPP_5.0.tar.gz already exists. Skipping download"
fi

if [ ! -e /home/ipopp/drl/tools/services.sh ]; then
  echo "Installing IPOPP software"
  cd /home/ipopp && tar -vxzf DRL-IPOPP_5.0.tar.gz
  chmod -R 755 /home/ipopp/IPOPP
  cd /home/ipopp/IPOPP && ./install_ipopp.sh
else
  echo "/home/ipopp/drl/tools/services.sh already exists. Skipping Install"
fi

echo "Listing IPOPP Versions"
/home/ipopp/drl/tools/list_version_info.sh

IPOPP_CHECK=$(/home/ipopp/drl/tools/list_version_info.sh | grep IPOPP)
echo "Version: $IPOPP_CHECK"

echo "IPOPP installation finished"

echo ""
echo "======================================================================"
echo ""
echo " Initial configuration complete."
echo " You must now start the instance and configure the IPOPP SPAs manually."
echo ""
echo " IPOPP Configuration:"
echo " By default IPOPP will only create level 1A and level 1B data products"
echo " To configure IPOPP to create level 2 data products,"
echo " the relevant level 2 SPAs must be enabled in the IPOPP dashboard"
echo ""
echo "======================================================================"

