Q = require 'q'
request = require 'request-promise'

follow = (changeId) ->
  followed = Q.defer()

  url = 'http://www.pathofexile.com/api/public-stash-tabs'
  url += "?id=#{changeId}" if changeId?

  request
    url: url
    gzip: true
  .then (data) ->
    res = JSON.parse(data)
    followed.reject(data) unless res?
    followed.resolve
      data: res.stashes
      nextChange: ->
        console.log "fetching changes from #{res.next_change_id}"
        follow(res.next_change_id)
  , (err) -> followed.reject(err)

  followed.promise

module.exports = follow