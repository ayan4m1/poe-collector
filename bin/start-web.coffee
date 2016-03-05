# pull in yaml in conf/
config = require('konfig')()

# basic app setup
express = require 'express'
app = express()

# deflate support
app.use require('compression')() if config.web.compress

# determine our webroot
path = require 'path'
root = path.resolve "#{__dirname}/../www"

console.log "web root at #{root}"

# pre-handle static requests
app.use express.static(root)

# cors support
app.use require('cors')({origin: config.web.hostname ? true})

# body parsing
bodyParser = require 'body-parser'
app.use bodyParser.json()
app.use bodyParser.urlencoded({extended: false})

# bind our routes here

# catch-all to redirect to angular bootstrapper
app.all '/*', (req, res) ->
  res.redirect('/index.html')

app.listen config.web.port
console.log "listening on port #{config.web.port}"