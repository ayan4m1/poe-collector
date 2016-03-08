angular
  .module 'poe.services', ['poe.constants', 'ngStorage', 'elasticsearch']
  # expose moment as a service for in-angular access and mocking
  .factory 'moment', ['$window', ($window) -> $window.moment]
  # watch socket events
  .factory 'watchService', ['primus', (primus) -> {
    init: ->
      primus.on('data', (data) ->
        console.log "got data: " + data
      )
  }]
  .service 'searchService', ['esFactory', 'searchHost', 'apiKey', (esFactory, searchHost, apiKey) ->
    esFactory
      host: "http://apikey:#{apiKey}@#{searchHost}"
      suggestCompression: true
  ]