follow = require './follower'

handle = (result) ->
  console.log "got one result with #{result.data.length} stashes"

  result.nextChange()
  .then(handle)
  .done() if result.nextChange?

follow()
.then handle
.catch (err) ->
  console.error err
.done()