'use strict'

forever = require 'forever-monitor'
scheduler = require 'node-schedule'

schedule = (cron, script) ->
  scheduler.scheduleJob(cron, ->
    forever.start([ 'coffee'].concat(script), {
      max: 1
    });
  );

schedule '30 23 * * *', [ '/home/node/poe-notifier/bin/index-update.coffee' ]
schedule '45 22 * * *', [ '/home/node/poe-notifier/bin/index-prune.coffee' ]
schedule '* */6 * * *', [ '/home/node/poe-notifier/bin/fetch-currency-web.coffee' ]
schedule '30 * * * *', [ '/home/node/poe-notifier/bin/clean-cache.coffee', '-f' ]
