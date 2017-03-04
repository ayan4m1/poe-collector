#!/usr/bin/env bash

NODE_ENV=production

run_forever ()
{
	if [ -n "$1" ]
	then
		forever start -e "logs/${1}-error.log" -o "logs/${1}-app.log" -c coffee "$1"
	fi

	return 0
}

echo "Updating..."
gulp update

echo "Starting..."
run_forever "bin/start-watcher.coffee"
run_forever "bin/start-emitter.coffee"
run_forever "bin/start-web.coffee"

