'use strict'

config = require('konfig')()
winston = require 'winston'

# rotates the log file for us
require('winston-daily-rotate-file')

logger = new (winston.Logger)(
  level: config.log.level ? 'info'
  transports: [
    new (winston.transports.Console)(),
    new (winston.transports.DailyRotateFile)(
      filename: 'log/.log'
      prepend: true
      datePattern: 'yyyy-MM-dd'
      level: config.log.level ? 'info'
    )
  ]
)

module.exports =
  as: logger
