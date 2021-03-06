#!/bin/bash
# Execute CI builds on taskcluster for Dockerflow!
# Note: this script was copied from https://github.com/mozilla/balrog/blob/master/scripts/push-dockerimage.sh

set -e

password_url="taskcluster/secrets/v1/secret/repo:github.com/mozilla-releng/funsize-balrogworker:branch:master"
artifact_url="taskcluster/queue/v1/task/${TASK_ID}/runs/${RUN_ID}/artifacts/public/docker-image-shasum256.txt"
artifact_expiry=$(date -d "+1 year" -u +%FT%TZ)
dockerhub_email=fkang@mozilla.com
dockerhub_username=mozillabalrog
dockerhub_password=$(curl ${password_url} | python -c 'import json, sys; a = json.load(sys.stdin); print a["secret"]["dockerhub_password"]')

if [ -z $dockerhub_password ]; then
    echo "Dockerhub password not set, can't continue!"
    exit 1
fi

echo "Retrieving version info"
commit=$(git rev-parse HEAD)
version=$(cat version.txt)
branch=$(git rev-parse --abbrev-ref HEAD)
date=$(date --utc +%Y-%m-%d-%H-%M)

echo "{
    \"commit\": \"${commit}\",
    \"version\": \"${version}\",
    \"source\": \"https://github.com/mozilla-releng/funsize-balrogworker\",
    \"build\": \"https://tools.taskcluster.net/task-inspector/#${TASK_ID}\"
}" > version.json


branch_tag="${branch}"
if [ "$branch" == "master" ]; then
    branch_tag="latest"
fi
date_tag="${branch}-${date}"

echo "Building Docker image"
docker build -t mozilla/balrogworker:${branch_tag} .
echo "Tagging Docker image with date tag"
docker tag mozilla/balrogworker:${branch_tag} "mozilla/balrogworker:${date_tag}"
echo "Logging into Dockerhub"
docker login -e $dockerhub_email -u $dockerhub_username -p $dockerhub_password
echo "Pushing Docker image"
docker push mozilla/balrogworker:${branch_tag}
docker push mozilla/balrogworker:${date_tag}

sha256=$(docker images --no-trunc mozilla/balrogworker | grep "${date_tag}" | awk '/^mozilla/ {print $3}')
echo "SHA256 is ${sha256}, creating artifact for it"
put_url=$(curl --retry 5 --retry-delay 5 --data "{\"storageType\": \"s3\", \"contentType\": \"text/plain\", \"expires\": \"${artifact_expiry}\"}" ${artifact_url} | python -c 'import json; import sys; print json.load(sys.stdin)["putUrl"]')
curl --retry 5 --retry-delay 5 -X PUT -H "Content-Type: text/plain" --data "${sha256}" "${put_url}"
echo 'Artifact created, all done!'
