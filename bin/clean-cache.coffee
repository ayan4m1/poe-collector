config = require('konfig')()

Q = require 'q'
fs = require 'fs'
moment = require 'moment'
inquirer = require 'inquirer'

log = require './logging'

statFile = Q.denodeify(fs.stat)
readDir = Q.denodeify(fs.readdir)
unlink = Q.denodeify(fs.unlink)

cacheConfig = config.cache.retention
retention = moment.duration(cacheConfig.interval, cacheConfig.unit)
cutoff = moment().subtract(retention)
cacheDir = "#{__dirname}/../cache"

isStale = (changeId) ->
  path = "#{cacheDir}/#{changeId}"
  statFile(path).then (stats) ->
    moment(stats.birthtime).isBefore(cutoff)

purgeCache = (list) ->
  for purgeItem in list
    path = "#{cacheDir}/#{purgeItem}"
    log.as.debug(path)
    unlink(path)

log.as.info("cutoff is #{cutoff.toISOString()}")
readDir(cacheDir)
  .catch(log.as.error)
  .then (changeIds) ->
    log.as.info("#{changeIds.length} total files in directory")
    toPurge = changeIds.filter(isStale)

    return log.as.info("no cache markers need to be purged") if toPurge.length is 0

    if process.argv[2] is '-f'
      purgeCache(toPurge)
      return log.as.info('forced cache purge')

    inquirer.prompt([{
      name: 'purge'
      type: 'confirm'
      default: false
      options: [ true, false ]
      message: "#{toPurge.length} cache markers that are older than #{retention.humanize()}"
    }])
      .catch(log.as.error)
      .then (res) ->
        return log.as.info('user requested exit') if res?.purge is false
        return unless res?.purge is true
        purgeCache(toPurge)
