#!/usr/bin/env bash

# DESCRIPTION:
# Manage YouTube subscription (or Invidious instances) via the command line
#   @author: PMK
#   @since: 2021/05
#   @license: GNU GPLv3
#   @dependencies: jq
#
# DEPENDENCIES:
# - jq (https://github.com/stedolan/jq)
# - GnuTLS (https://gitlab.com/gnutls/gnutls)
#
# USING SERVICE FROM:
# - feed2json (https://feed2json.org)


##
# Global variables
##

VERSION="0.0.1"
DEBUG=0
DEFAULT_STORAGE_FILE="$HOME/.myts"
INVIDIOUS_INSTANCES_JSON="https://api.invidious.io/instances.json?sort_by=type,health,users"
USER_AGENT="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_13_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/70.0.3538.77 Safari/537.36"
DEFAULT_SERVER_PORT="3210"
USE_INVIDIOUS=0
CHANNEL_AMOUNT_LIMIT="50"
VIDEO_AMOUNT_LIMIT="48"
I=$'\a'	#sets variable I to "system bell" using ansi-c style quoting (bash/ksh)


##
# Imports
##

# Import getoptions
source ./vendors/lib/getoptions.sh
source ./vendors/lib/getoptions_help.sh
source ./vendors/lib/getoptions_abbr.sh


##
# Parse (sub)commands, options and arguments
##
parser_definition() {
  setup  REST help:usage abbr:true width:"22,22" -- \
         "Usage: ${2##*/} [global options...] [command] [options...] [arguments...]"
  msg -- '' '(c) PMK' '-GNU GPLv3' ''
  msg -- 'Manage YouTube subscriptions via the command line' ''
  msg -- 'With MYTS you can easily manage YouTube channel subscriptions via the command line, without the need of a user account on YouTube. Your subscriptions are stored local in a file. Run the subcommand "server" to start a webserver what will display all the latest videos of the channels you subscribed to.' ''
  msg -- '' 'Options:'
  param  FILE -f --file -- "File containing subscriptions (default: $DEFAULT_STORAGE_FILE)"
  disp   :usage  -h --help -- "Show this help"
  disp   VERSION -v --version -- "Show the version"
  flag   DEBUG  --debug -- "Run in debug mode"
  msg -- '' 'Commands:'
  cmd subscribe -- "Subscribe to a YouTube channel."
  cmd unsubscribe -- "Unsubscribe from a YouTube channel."
  cmd server -- "Start a webserver to display the latest videos of the subscribed YouTube channels."
  msg -- '' 'Examples:'
  msg -- '  Subscribe to a YouTube channel' "  \$ ${2##*/} subscribe https://youtube.com/channel/UCBR8-60-B28hp2BmDPdntcQ" ''
  msg -- '  Start a webserver with a custom port and a custom file' "  \$ ${2##*/} -f ./my_subscribed_channels server -p 8080"
}

parser_definition_subscribe() {
  setup  REST help:usage abbr:true -- \
    "Usage: ${2##*/} subscribe [options...] [urls...]"
  msg -- '' 'Subscribe to a YouTube channel via the provided urls.' ''
  msg -- 'Options:'
  disp   :usage  -h --help
}

parser_definition_unsubscribe() {
  setup  REST help:usage abbr:true -- \
    "Usage: ${2##*/} unsubscribe [options...] [urls...]"
  msg -- '' 'Unsubscribe from a YouTube channel you have subscribed to, via the provided urls.' ''
  msg -- 'Options:'
  disp   :usage  -h --help
}

parser_definition_server() {
  setup  REST help:usage abbr:true -- \
    "Usage: ${2##*/} server [options...]"
  msg -- '' 'Start a webserver to display an overview of your YouTube subscriptions.' ''
  msg -- 'Options:'
  param  SERVER_PORT  -p --port -- "Run the webserver on this port (default: $DEFAULT_SERVER_PORT)"
  flag   USE_INVIDIOUS -i --invidious -- "Use the best Invidious server instead of using YouTube"
  disp   :usage  -h --help
}


##
# Wrapped functions
##

# Run dependency 'jq' what is installed, or in a specific directory
safe_jq() {
  if hash jq 2>/dev/null; then
    jq "$@"
  else
    echo "Dependency 'jq' not found!"
    exit 1
  fi
}

# Run GNU echo
safe_echo() {
  if echo --version >/dev/null 2>&1; then
    echo "$@"
  else
    if hash gecho 2>/dev/null; then
      gecho "$@"
    else
      print_error "Dependency 'gecho' not found"
      exit 1
    fi
  fi
}

# A better sleep function
safe_sleep() {
  if hash sleep 2>/dev/null; then
    sleep $1
  else
    read -r -t "$1" <> <(:) || :
  fi
}

# Run GNU date
safe_date() {
  if date --version >/dev/null 2>&1; then
    date "$@"
  else
    if hash gdate 2>/dev/null; then
      gdate "$@"
    else
      print_error "Dependency 'gdate' not found"
      exit 1
    fi
  fi
}


##
# Utility functions
##

# Print error message
print_error() {
  safe_echo -e "\033[0;91m[ERROR] \033[0;31m$1\033[0m"
}

# Print error message and exit the script
fail() {
  print_error "$1"
  exit 1
}

# Print warning message
function print_warning {
  safe_echo -e "\033[0;93m[WARN]  \033[0;33m$1\033[0m"
}

# Print log message if --debug is used with optional details
print_log() {
  if test -z "$1"; then
    print_error "Missing required argument in 'log'"
    exit 1
  fi

  if test "$DEBUG" == "1"; then
    safe_echo -e "\033[0;37m[LOG]   \033[0;90m$1\033[0m"

    if test "$2" != ""; then
      safe_echo "$2" | safe_jq '.'
    fi
  fi
}


######


# Convert input date to relative date
# Taken from https://unix.stackexchange.com/a/451216 but modified
relative_date() {
  local SEC_PER_MINUTE=$((60))
  local   SEC_PER_HOUR=$((60*60))
  local    SEC_PER_DAY=$((60*60*24))
  local  SEC_PER_MONTH=$((60*60*24*30))
  local   SEC_PER_YEAR=$((60*60*24*365))

  local last_unix="$(safe_date --date="$1" +%s)" # convert date to unix timestamp
  local now_unix="$(safe_date +'%s')"

  local delta_s=$(( now_unix - last_unix ))

  if (( delta_s < SEC_PER_MINUTE )); then
    safe_echo $((delta_s))" seconds ago"
    return
  elif (( delta_s < SEC_PER_HOUR )); then
    safe_echo $((delta_s / SEC_PER_MINUTE))" minutes ago"
    return
  elif (( delta_s < SEC_PER_DAY )); then
    safe_echo $((delta_s / SEC_PER_HOUR))" hours ago"
    return
  elif (( delta_s < SEC_PER_MONTH )); then
    safe_echo $((delta_s / SEC_PER_DAY))" days ago"
    return
  elif (( delta_s < SEC_PER_YEAR )); then
    safe_echo $((delta_s / SEC_PER_MONTH))" months ago"
    return
  else
    safe_echo $((delta_s / SEC_PER_YEAR))" years ago"
    return
  fi
}

# Returns "true" if input contains a valid YouTube channel URI
is_valid_channel_uri() {
  if test -z "$1"; then
    fail "Missing required argument in 'is_valid_channel_uri'"
  fi

  [[ $1 =~ \/channel\/UC[a-zA-Z0-9_-]{22}\/?$ ]] && safe_echo "true" || safe_echo "false"
}

# Returns the YouTube channel ID from the input
get_channel_id_from_uri() {
  if test -z "$1"; then
    fail "Missing required argument in 'get_channel_id_from_uri'"
  fi

  local channel_id="${1##*/UC}"
  safe_echo "UC${channel_id%/}"
}

# Returns "true" if input is present in FILE
is_present_in_storage_file() {
  if test -z "$1"; then
    fail "Missing required argument in 'is_present_in_storage_file'"
  fi

  cat $STORAGE_FILE | grep -F "$1" >/dev/null && safe_echo "true" || safe_echo "false"
}

# Add YouTube channel ID to file STORAGE_FILE
add_channel_id_to_storage_file() {
  if [[ ! $(is_valid_channel_uri $1) ]]; then
    print_warning "Skipped adding $1 to storage file, because it is an invalid YouTube channel ID."
  elif [[ $(is_present_in_storage_file $1) == "true" ]]; then
    print_warning "Skipped adding YouTube channel ID to storage file, because it is already present: $1"
  else
    safe_echo -en "$1\n" >> $STORAGE_FILE
    print_log "Added $1 to storage file $STORAGE_FILE"
    safe_echo "Subscribed."
  fi
}

# Remove YouTube channel ID from file STORAGE_FILE
remove_channel_id_from_storage_file() {
  if [[ ! $(is_valid_channel_uri $1) ]]; then
    print_warning "Skipped removing $1 from storage file, because it is an invalid YouTube channel ID."
  elif [[ ! $(is_present_in_storage_file $1) == "true" ]]; then
    print_warning "Skipped removing YouTube channel ID from storage file, because it is not present: $1"
  else
    cat $STORAGE_FILE | grep -F -v "$1" > "$STORAGE_FILE.tmp"
    mv "$STORAGE_FILE.tmp" $STORAGE_FILE
    print_log "Removed $1 from storage file $STORAGE_FILE"
    safe_echo "Unsubscribed."
  fi
}

# Get the best instance according to the list of instances on invidious.io
get_best_invidious_instance() {
  local curl_response=$(curl -sSL \
    -H "User-Agent: $USER_AGENT" \
    "$INVIDIOUS_INSTANCES_JSON" \
    2>/dev/null)

  # Filters .onion and .i2p
  safe_echo $curl_response | safe_jq 'map(select(.[1].type == "https")) | .[0][1].uri' | tr -d '"'
}

# Set the instance globally
set_instance() {
  INSTANCE="https://youtube.com/"
  if test "$USE_INVIDIOUS" == "1"; then
    INSTANCE=$(get_best_invidious_instance)
  fi

  # Make sure to end without a slash
  INSTANCE="${INSTANCE%\/}"
}

# Get thumbnail URL
get_thumbnail() {
  local thumb_url="https://i.ytimg.com/"
  if test "$USE_INVIDIOUS" == "1"; then
    thumb_url=$INSTANCE
  fi

  safe_echo "${thumb_url%\/}/vi/$1/mqdefault.jpg"
}

# Get RSS feed URL
get_feed_url() {
  if test -z "$1"; then
    fail "Missing required YouTube channel ID in 'get_feed'"
  fi

  local feed_url="https://www.youtube.com/feeds/videos.xml?channel_id=$1"
  if test "$USE_INVIDIOUS" == "1"; then
    feed_url="$INSTANCE/feed/channel/$1"
  fi

  safe_echo "https://feed2json.org/convert?url=$feed_url"
}

# Get all videos from all subscribed channels, sorted by published_date, limited and return JSON
get_latest_videos_from_all_channel_ids_in_storage_file() {
  local i=0
  local all_videos_json=''
  while read channel; do
    local feed_url=$(get_feed_url "$channel")
    local curl_response=$(curl -sSL \
      -H "User-Agent: $USER_AGENT" \
      "$feed_url" \
      2>/dev/null)
    all_videos_json="$all_videos_json$(safe_echo "$curl_response" | jq -c --arg channelid $channel '[limit(3;.items[])] | .[] += {"channel_id":$channelid}')"

    # Cool down the requests on half way
    # if $curl_response == "Too Many Requests"; then sleep 2
    if test "$i" == "$CHANNEL_AMOUNT_LIMIT"; then
      safe_sleep 2
    fi

    i=$i+1
  done < $STORAGE_FILE

  safe_echo $all_videos_json | sed -E -e 's/yt:video://g' -e 's|\}\]\[\{|\},\{|g' | jq -c 'sort_by(.date_published) | reverse'
}

# Generate HTML
generate_html() {
  local template_start=$(cat <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta http-equiv="X-UA-Compatible" content="IE=edge">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>MYTS</title>
  <style>
    body {
      margin: 2em;
    }
    section {
      display: grid;
      grid-gap: 1em;
      grid-template-columns: repeat(auto-fit, minmax(20%, 1fr));
    }
    .thumb {
      width: 100%;
    }
  </style>
</head>
<body>
  <main>
    <h1>Latest videos</h1>
    <p><sup>Using ${INSTANCE#https:\/\/}</sup></p>
    <section>
EOF
)

local template_video=$(cat <<EOF
      <article>
        <a href="$INSTANCE/watch?v=@1" target="_blank">
          <img class="thumb" src="$(get_thumbnail '@1')" alt="@2" />
          <p>@2</p>
        </a>
        <p>by <a href="${INSTANCE}/@4" target="_blank">@5</a></p>
        <p><small>@3</small></p>
      </article>
EOF
)

local template_end=$(cat <<EOF
    </section>
  </main>
</body>
</html>
EOF
)

  safe_echo $template_start
  while IFS= read -r video; do
    local videoid=$(safe_echo "$video" | jq ".guid" | tr -d '"')
    local title=$(safe_echo "$video" | jq ".title" | tr -d '"')
    local rawpubdate=$(safe_echo "$video" | jq ".date_published" | tr -d '"')
    local pubdate=$(relative_date "$rawpubdate")
    local channelid=$(safe_echo "$video" | jq ".channel_id" | tr -d '"')
    local channelname=$(safe_echo "$video" | jq ".author.name" | tr -d '"')

    safe_echo $template_video | sed \
      -e "s${I}@1${I}$videoid${I}g" \
      -e "s${I}@2${I}$title${I}g" \
      -e "s${I}@3${I}$pubdate${I}g" \
      -e "s${I}@4${I}$channelid${I}g" \
      -e "s${I}@5${I}$channelname${I}g"
  done < <(get_latest_videos_from_all_channel_ids_in_storage_file | jq -cr '.[]')
  safe_echo $template_end
}

# Initialize storage file if given FILE does not exist
init_storage_file() {
  STORAGE_FILE=$DEFAULT_STORAGE_FILE

  if test ! -z "$FILE"; then
    STORAGE_FILE=$FILE
  fi

  if test ! -f "$STORAGE_FILE"; then
    touch -f "$STORAGE_FILE"
    print_log "Created empty storage file at $STORAGE_FILE"
  fi
}


# Execute command "subscribe"
cmd_subscribe() {
  if test -z "$1"; then
    print_warning "No YouTube channel URL provided to subscribe."
    read -p "URL: " -r

    cmd_subscribe "$REPLY"
  else
    local subscribe_urls_i=0
    while [ $# -gt 0 ] && subscribe_urls_i=$((subscribe_urls_i + 1)); do
      if [[ $(is_valid_channel_uri "$1") == "true" ]]; then
        add_channel_id_to_storage_file $(get_channel_id_from_uri "$@")
      fi
      shift
    done
  fi
}

# Execute command "unsubscribe"
cmd_unsubscribe() {
  if test -z "$1"; then
    print_warning "No YouTube channel URL provided to unsubscribe."
    read -p "URL: " -r

    cmd_unsubscribe "$REPLY"
  else
    local unsubscribe_urls_i=0
    while [ $# -gt 0 ] && unsubscribe_urls_i=$((unsubscribe_urls_i + 1)); do
      if [[ $(is_valid_channel_uri "$1") == "true" ]]; then
        remove_channel_id_from_storage_file $(get_channel_id_from_uri "$@")
      fi
      shift
    done
  fi
}

# Execute command "server"
cmd_server() {
  safe_echo -n "Generating page with latest videos of your subscriptions. Please wait..."

  local html=$(generate_html)

  safe_echo " Done!"

  if test -z "$SERVER_PORT"; then
    SERVER_PORT=$DEFAULT_SERVER_PORT
  fi

  safe_echo -e "Access the webserver at \e[4mhttp://127.0.0.1:$SERVER_PORT\e[0m"
  safe_echo "(to close the webserver, press Ctrl and C keys simultaneously...)"

  local response="HTTP/1.1 200 OK\r\nConnection: keep-alive\r\n\r\n$html\r\n"
  while { safe_echo -en "$response"; } | nc -l "$SERVER_PORT" >/dev/null; do
    safe_echo -n ""
  done
}


#######


##
# Init
##
eval "$(getoptions parser_definition parse "$0")"
parse "$@"
eval "set -- $REST"

print_log "VERSION=$VERSION"
print_log "DEBUG=$DEBUG"

if [ $# -gt 0 ]; then
  cmd=$1
  shift

  case $cmd in
    subscribe)
      eval "$(getoptions parser_definition_subscribe parse "$0")"
      parse "$@"
      eval "set -- $REST"

      init_storage_file
      set_instance
      cmd_subscribe "$@"
      ;;
    unsubscribe)
      eval "$(getoptions parser_definition_unsubscribe parse "$0")"
      parse "$@"
      eval "set -- $REST"

      init_storage_file
      set_instance
      cmd_unsubscribe "$@"
      ;;
    server)
      eval "$(getoptions parser_definition_server parse "$0")"
      parse "$@"
      eval "set -- $REST"

      init_storage_file
      set_instance
      cmd_server
      ;;
    --) # no subcommand, arguments only
  esac
fi
