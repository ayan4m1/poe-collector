angular
  .module 'poe.services', ['poe.constants', 'ngStorage', 'elasticsearch']
  # expose moment as a service for in-angular access and mocking
  .factory 'moment', ['$window', ($window) -> $window.moment]
  # watch socket events
  .factory 'watchService', ['$rootScope', 'primus', ($rootScope, primus) ->
    watchService = {
      init: ->
        primus.on 'open', ->
          $rootScope.$broadcast 'watcher:opened'
        primus.on 'close', ->
          $rootScope.$broadcast 'watcher:closed'

        primus.on('data', (data) ->
          console.log "got data: " + data
        )
    }
    watchService
  ]
  .service 'searchService', ['esFactory', 'searchHost', 'apiKey', (esFactory, searchHost, apiKey) ->
    esFactory
      host: "http://apikey:#{apiKey}@#{searchHost}"
      suggestCompression: true
  ]