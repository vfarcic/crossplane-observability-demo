#!/bin/sh
gum confirm "
We are going to create some videos on the silly demo app available at http://sillydemo.$INGRESS_IP.nip.io

## You will need following tools installed:
|Name          |Required             |More info                                 |
|--------------|---------------------|------------------------------------------|
|curl          |Yes                  |'https://curl.se/download.html'           |

Ready?
" || exit 0

NUMBER_OF_REQUESTS=$(gum input --placeholder "How many videos do you want to create?" --value "$NUMBER_OF_REQUESTS")
START_ID=$(gum input --placeholder "At which video id should we start?" --value "$START_ID")

for i in $(seq 1 "$NUMBER_OF_REQUESTS");
do
  id=$(("$START_ID" + "$i"))
  curl -X POST -s -o /dev/null "http://silly-demo.$INGRESS_IP.nip.io/video?id=$id&title=Amazing%20Video%20%23$id" &
done

wait
