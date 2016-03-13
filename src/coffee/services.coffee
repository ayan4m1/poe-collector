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
  .service 'SearchService', ['esFactory', 'searchHost', 'apiKey', 'percentiles',
  (esFactory, searchHost, apiKey, percentiles) ->
    es = esFactory
      host: "http://apikey:#{apiKey}@#{searchHost}"
      suggestCompression: true

    SearchService =
      es: es
      getCurrencies: ->
        @es.search(
          index: 'index'
          size: 0
          body:
            query:
              bool:
                must: [
                  { term: { 'attributes.frameType': { value: 5 } } }
                ]
            aggs:
              name:
                terms:
                  field: 'info.name'
        ).then (rawData) -> bucket.key for bucket in rawData.aggregations.name.buckets
      getCurrencyTrades: ->
        @es.search(
          index: 'index'
          size: 50
          body:
            query:
              bool:
                must: [
                  { term: { 'attributes.frameType': { value: 5 } } }
                  { term: { 'shop.hasPrice': 'YES' } }
                  { term: { 'shop.verified': 'YES' } }
                  { range: { 'shop.chaosEquiv': { 'gt': 0 } } }
                  { range: { 'properties.stackSize.current': { gt: 0, lt: 2 } } } # single unit
                ]
            aggs:
              name:
                terms:
                  field: 'info.name'
                aggs:
                  priceStats:
                    stats:
                      field: 'shop.chaosEquiv'
                      #script: "doc['shop.chaosEquiv'].value / doc['properties.stackSize.current'].value"
                  pricePercentile:
                    percentiles:
                      field: 'shop.chaosEquiv'
                      percents: percentiles
        )
      getItem: (options) ->
        @es.search(
          index: 'index'
          size: options.size ? 50
          sort: [
            'shop.chaosEquiv'
          ]
          body:
            query:
              filtered:
                query:
                  match_phrase:
                    { 'info.tokenized.fullName': options.name }
                filter:
                  bool:
                    must: [
                      { term: { 'shop.hasPrice': 'YES' } }
                      { term: { 'shop.verified': 'YES' } }
                      { term: { 'attributes.lockedToCharacter': 'no' } }
                      { term: { 'attributes.league': options.league ? 'Perandus' } }
                      { term: { 'attributes.rarity': options.rarity ? 'Unique' } }
                      { range: { 'shop.chaosEquiv': { 'gt': options.minPrice ? 0 } } }
                    ]
            ###
            aggs:
              currency:
                terms:
                  field: 'shop.currency'
                  min_doc_count: 4
                aggs:
                  price:
                    percentiles:
                      field: 'shop.chaosEquiv'
                      percents: $scope.percentiles
            ###
        )

    SearchService
  ]