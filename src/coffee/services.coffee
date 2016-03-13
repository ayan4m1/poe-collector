angular
  .module 'poe.services', ['poe.constants', 'ngStorage', 'elasticsearch']
  # expose moment as a service for in-angular access and mocking
  .factory 'moment', ['$window', ($window) -> $window.moment]
  # watch socket events
  .factory 'SocketService', ['$rootScope', 'primus', ($rootScope, primus) ->
    SocketService = {
      attach: (scope, event, cb) ->
        handler = $rootScope.$on event, cb
        scope.$on 'destroy', handler
        return
    }

    primus.on 'data', (data) ->
      $rootScope.$emit 'watcher:item', data
    primus.on 'open', ->
      $rootScope.$emit 'watcher:opened'
    primus.on 'close', ->
      $rootScope.$emit 'watcher:closed'

    SocketService
  ]
  .service 'searchService', ['esFactory', 'searchHost', 'apiKey', (esFactory, searchHost, apiKey) ->
    esFactory
      host: "http://apikey:#{apiKey}@#{searchHost}"
      suggestCompression: true
  ]