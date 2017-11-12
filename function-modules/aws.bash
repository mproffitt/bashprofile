#!/bin/bash

##
# Packs the current directory for uploading as a function
#
function awspack()
{
    if [ -z "${VIRTUAL_ENV}" ] ; then
        echo "No Virtual environment set. Nothing to pack" >&2
        return 1
    fi

    local cwd=$(pwd)
    local zipname=$(basename $(pwd))
    # should normally be the only copy of a site-packages file
    cd $(python -c "import sys; print([path for path in sys.path if path.endswith('site-packages')][0])")
    [ -f "/tmp/${zipname}.zip" ] && rm -f /tmp/${zipname}.zip
    zip -r9 /tmp/${zipname}.zip .
    cd $cwd
    zip -rg /tmp/${zipname}.zip .
}

##
# Uploads the current virtualenv as a lambda to AWS s3
#
function s3upload()
{
    local timeout=3
    local memory_size=1024
    local zipname=$(basename $(pwd))
    local function_name=${zipname}
    local module_name=$(sed -r 's/(^|-)(\w)/\U\2/g' <<<${zipname})
    local role="service-role/SampleLambdaRole"
    local handler="${module_name}.handler"
    [ ! -z "$1" ] && role="$1"
    [ ! -z "$2" ] && handler="$2"

    local region=$(awk '/region/ {print $NF}' ~/.aws/config)
    local servicearn="arn:aws:iam::${AWS_ACCOUNT}:role/${role}"
    if ! awspack ; then
        return 1
    fi

    aws lambda create-function \
        --region ${region} \
        --function-name ${function_name} \
        --zip-file fileb:///tmp/${zipname}.zip \
        --role ${servicearn} \
        --handler ${handler} \
        --runtime python3.6 \
        --timeout ${timeout} \
        --memory-size ${memory_size}
    if [ $? -ne 0 ]; then
        echo "Failed to create function, trying update instead"
        aws lambda update-function-code \
            --function-name "arn:aws:lambda:${region}:${AWS_ACCOUNT}:function:${function_name}" \
            --zip-file fileb:///tmp/${zipname}.zip
    fi
}

function s3perm()
{
    local bucket='dxcsample'
    local function=$(basename $(pwd))
    [ ! -z "$1" ] && bucket="$1"
    [ ! -z "$2" ] && function="$2"

    local arn="arn:aws:s3:::${bucket}"
    local statement="$(basename $(pwd))stmt"
    aws lambda add-permission \
        --function-name ${function} \
        --region $(awk '/region/ {print $NF}' ~/.aws/config) \
        --statement-id ${statement} \
        --action "lambda:InvokeFunction" \
        --principal s3.amazonaws.com \
        --source-arn ${arn} \
        --source-account ${AWS_ACCOUNT}
}
