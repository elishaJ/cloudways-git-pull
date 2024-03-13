#!/bin/bash

Retrieve input variables
email="$EMAIL"
api_key="$API_KEY"
app_id="$APP_ID"
server_id="$SERVER_ID"
branch_name="$BRANCH_NAME"
deploy_path="$DEPLOY_PATH"
max_retries=10
is_deployed=
dir=$(pwd)
BASE_URL="https://api.cloudways.com/api/v1"
qwik_api="https://us-central1-cw-automations.cloudfunctions.net"

# Fetch access token
get_token() {
    echo "Retrieving access token"
    response=$(curl -s -X POST --location "$BASE_URL/oauth/access_token" \
        -w "%{http_code}" \
        --header 'Content-Type: application/x-www-form-urlencoded' \
        --data-urlencode 'email='$email'' \
        --data-urlencode 'api_key='$api_key'')

    http_code="${response: -3}"
    body="${response::-3}"

    if [ "$http_code" != "200" ]; then
        echo "Error: Failed to retrieve access token. Invalid credentials."
        exit 1
    else
        # Parse the access token and set expiry time to 10 seconds
        access_token=$(echo "$body" | jq -r '.access_token')
        expires_in=$(echo "$body" | jq -r '.expires_in')
        expiry_time=$(( $(date +%s) + $expires_in ))
        echo "Access token generated."
    fi
}

check_token_validity() {
    current_time=$(date +%s)
    if [ "$current_time" -ge "$expiry_time" ]; then       
        validity="invalid"
        is_valid=false
        get_token
    fi
}

pull_git_repo() {
    echo "Initiating pull request"
    if [ -z "$deploy_path" ]; then
        response=$(curl -s -X POST --location "$BASE_URL/git/pull" \
        --header 'Content-Type: application/x-www-form-urlencoded' \
        --header 'Accept: application/json' --header 'Authorization: Bearer '$access_token'' \
        -d 'server_id='$server_id'&app_id='$app_id'&branch_name='$branch_name'')
    else
        response=$(curl -s -X POST --location "$BASE_URL/git/pull" \
        --header 'Content-Type: application/x-www-form-urlencoded' \
        --header 'Accept: application/json' --header 'Authorization: Bearer '$access_token'' \
        -d 'server_id='$server_id'&app_id='$app_id'&branch_name='$branch_name'&deploy_path='$deploy_path'')
    fi
    operation_id=$(echo "$response" | jq -r '.operation_id')

    # Handle case where operation is already in progress
    retry_count=0
    while [[ "$(echo "$response" | jq -r '.message')" =~ ^"An operation is already in progress" ]] && [ $retry_count -lt $max_retries ]; do
        echo "An operation is already in progress for app ID: $app_id"
        echo ""
        echo "Putting the script to sleep.."
        echo ""
        sleep 10
        echo "Trying again..."
        check_token_validity

        if [ -z "$deploy_path" ]; then
            response=$(curl -s -X POST --location "$BASE_URL/git/pull" \
            --header 'Content-Type: application/x-www-form-urlencoded' \
            --header 'Accept: application/json' --header 'Authorization: Bearer '$access_token'' \
            -d 'server_id='$server_id'&app_id='$app_id'&branch_name='$branch_name'')
        else
            response=$(curl -s -X POST --location "$BASE_URL/git/pull" \
            --header 'Content-Type: application/x-www-form-urlencoded' \
            --header 'Accept: application/json' --header 'Authorization: Bearer '$access_token'' \
            -d 'server_id='$server_id'&app_id='$app_id'&branch_name='$branch_name'&deploy_path='$deploy_path'')
        fi
        ((retry_count++))
    done
    sleep 5
    echo "Checking operation status"
    # Wait for the operation to complete
    while true; do
        operation_response=$(curl -s "$BASE_URL/operation/$operation_id" --header 'Authorization: Bearer '$access_token'')
        operation_status=$(echo $operation_response | jq -r '.operation.status')
        is_completed=$(echo $operation_response | jq -r '.operation.is_completed')
        if [ "$operation_status" == "Operation completed" ]; then
            echo "Git pull successful"
            is_deployed=true
            echo "is_deployed=$is_deployed" >> $GITHUB_OUTPUT
            break
        fi
        if [ "$is_completed" == "-1" ]; then
            operation_message=$(curl -s "$BASE_URL/operation/$operation_id" --header 'Authorization: Bearer '$access_token'' | jq -r '.operation.message')
            echo "Git pull failed. Error message: $operation_message"
            is_deployed=false
            echo "is_deployed=$is_deployed" >> $GITHUB_OUTPUT
            break
        fi
        sleep 5
    done
}

get_token
pull_git_repo
