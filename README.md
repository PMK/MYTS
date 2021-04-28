# MYTS - Manage YouTube subscriptions (or Invidious instances) via the command line

With MYTS you can easily manage YouTube channel subscriptions via the command line. Your subscriptions are stored local in a file. Run the subcommand "server" to start a webserver what will display all the latest videos of the channels you subscribed to.

![Command line example](https://github.com/pmk/myts/blob/master/example/1-command-line.png?raw=true)

## Dependencies
- jq: https://github.com/stedolan/jq

## Using service from
- feed2json (https://feed2json.org)

# Commands

For every command you can pass `--help` for more details.

## `subscribe`

Subscribe to a YouTube channel. It will save the YouTube channel ID in a file.

## `unsubscribe`

Unsubscribe from a YouTube channel.

## `server`

Start a webserver to display the latest videos of the subscribed YouTube channels.

![Webserver example](https://github.com/pmk/myts/blob/master/example/2-webserver.png?raw=true)

# Shout out

- getoptions (https://github.com/ko1nksm/getoptions/)
- jq (https://github.com/stedolan/jq)
- feed2json (https://feed2json.org)
- Invidious (https://github.com/iv-org/invidious)

# License

GNU GPLv3
