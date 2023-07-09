#!/bin/sh

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
grep -Pv '\s*^#' "$1" |
  # read will skip empty fields of optional parameters, so have to use multiple calls to cut instead
  while IFS= read -r line
  do
    #ARTIST [ALBUM] TITLE [TRACKNUM] LENGTH RATING TIMESTAMP [MUSICBRAINZ_TRACKID]
    artist=$(   echo "$line" | cut -d "	" -f 1)
    album=$(    echo "$line" | cut -d "	" -f 2)
    track=$(    echo "$line" | cut -d "	" -f 3)
    tracknr=$(  echo "$line" | cut -d "	" -f 4)
    duration=$( echo "$line" | cut -d "	" -f 5)
    rating=$(   echo "$line" | cut -d "	" -f 6)
    timestamp=$(echo "$line" | cut -d "	" -f 7)
    mbid=$(     echo "$line" | cut -d "	" -f 8)

    [ "$timezone" = 'UNKNOWN' ] && timestamp=$((timestamp - tz_offset))
    if [ "$rating" != "L" ]; then
      :
    else
      JSON='
      {
        "listen_type": "single",
        "payload": [
          {
            "listened_at": '"$timestamp"',
            "track_metadata": {
              "artist_name": "'"$artist"'",
              '"$( [ -n "$album" ] && echo '"release_name": "'"$album"'",' )"'
              "track_name": "'"$track"'",
              "additional_info": {
                "mediaplayer": "'"$client"'",
                '"$( is_valid_mbid "$mbid" && echo '"release_mbid": "'"$mbid"'",' )"'
                '"$( [ -n "$tracknr" ] && echo '"tracknumber": "'"$tracknr"'",' )"'
                "duration": "'"$duration"'"
              }
            }
          }
        ]
      }'
      #echo "$JSON"
      headerfile=$(mktemp)
      if curl 'https://api.listenbrainz.org/1/submit-listens' --header "Authorization: Token $auth_token" --fail-with-body -D "$headerfile" --json "$JSON"
      then
        remaining=$(grep -oP "x-ratelimit-remaining: \K\d+" "$headerfile")
        echo remaining="$remaining"
        if [ "$remaining" -lt 1 ]; then
          resetin=$(grep -oP "x-ratelimit-reset-in: \K\d+" "$headerfile")
          echo sleeping "$resetin"
          sleep "$resetin"
        fi
      else
        echo Scrobble failed: "$artist - $album - $track"
        echo "$artist	$album	$track	$tracknr	$duration	$rating	$timestamp	$mbid" >> "$1".failed
      fi
      rm "$headerfile"

    fi

  done
