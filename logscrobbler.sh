#!/bin/sh
# shellcheck disable=SC2016

if [ "$#" -ne 1 ]; then
    echo "Please provide precisely one parameter, the .scrobbler.log file"
fi

is_valid_mbid() {
   echo "$1" | grep -P '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' > /dev/null
}

auth_token=""
client=$(head "$1" | grep -Po '#CLIENT/\K.*')
timezone=$(head "$1" | grep -Po '#TZ/\K.*')
tz_offset=$(date +%:z | awk '{print substr($1, 1, 1) substr($1, 2, 2)*60*60} + substr($1, 4, 2) * 60')

submit() {
  #echo "$JSON" | jq
  headerfile=$(mktemp)
  if curl 'https://api.listenbrainz.org/1/submit-listens' \
    --header "Authorization: Token $auth_token" \
    --fail-with-body -D "$headerfile" \
    --json "$(echo "$JSON" | jq --compact-output)"
  then
    echo "Successfully submited $payload_listens listens"
    remaining=$(grep -oP "x-ratelimit-remaining: \K\d+" "$headerfile")
    echo remaining="$remaining"
    if [ "$remaining" -lt 1 ]; then
      resetin=$(grep -oP "x-ratelimit-reset-in: \K\d+" "$headerfile")
      echo sleeping "$resetin"
      sleep "$resetin"
    fi
  else
    echo "Failed to submit $payload_listens listens"
    echo "$JSON" >> "$1".failed
  fi
  rm "$headerfile"
  payload_listens=0
}

payload_listens=0
while IFS= read -r line
  do
    (echo "$line" | grep -P '^\s*#') && continue # Ignore comments
    #ARTIST [ALBUM] TITLE [TRACKNUM] LENGTH RATING TIMESTAMP [MUSICBRAINZ_TRACKID]
    artist=$(   echo "$line" | cut -d "	" -f 1)
    album=$(    echo "$line" | cut -d "	" -f 2)
    track=$(    echo "$line" | cut -d "	" -f 3)
    tracknr=$(  echo "$line" | cut -d "	" -f 4)
    duration=$( echo "$line" | cut -d "	" -f 5)
    rating=$(   echo "$line" | cut -d "	" -f 6)
    timestamp=$(echo "$line" | cut -d "	" -f 7)
    mbid=$(     echo "$line" | cut -d "	" -f 8)

    [ "$rating" != "L" ] && continue # Ignore skipped tracks

    [ "$timezone" = 'UNKNOWN' ] && timestamp=$((timestamp - tz_offset))
    if [ "$payload_listens" -lt 1 ]; then
      JSON='
      {
        "listen_type": "import",
        "payload": ['
        payload_listens=0
    else
      JSON="$JSON"','
    fi
    JSON="$JSON$(jq -n \
      '{
         "listened_at": $timestamp,
         "track_metadata": {
           "artist_name": $artist,
           '"$( [ -n "$album" ] && echo '"release_name": $album,' )"'
           "track_name": $track,
           "additional_info": {
             "mediaplayer": $client,
             '"$( is_valid_mbid "$mbid" && echo '"release_mbid": $mbid,' )"'
             '"$( [ -n "$tracknr" ] && echo '"tracknumber": $tracknr,' )"'
             "duration": $duration
           }
         }
       }' \
      --argjson timestamp "$timestamp"    \
      --arg     artist    "$artist"       \
      --arg     album     "$album"        \
      --arg     track     "$track"        \
      --arg     client    "$client"       \
      --arg     mbid      "$mbid"         \
      --argjson tracknr   "${tracknr:-0}" \
      --argjson duration  "$duration"
      # tracknr has a default so jq won't complain if it's missing
    )"
    payload_listens=$((payload_listens + 1))
    if [ "$payload_listens" -eq 1000 ]; then
      JSON="$JSON"'
        ]
      }'
      submit "$@"
    fi
  done <"$1"
if [ "$payload_listens" -ge 1 ]; then
      JSON="$JSON"'
        ]
      }'
  submit "$@"
fi

