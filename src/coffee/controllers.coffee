angular
  .module 'poe.controllers', [ 'poe.constants', 'poe.services' ]
  .controller 'CurrencyCtrl', ['$scope', 'primus', 'chaosValues', 'watchService', ($scope, primus, chaosValues, watchService) ->
    watchService.init()

    $scope.currencies = []
    $scope.currencies.push(key) for key, value of chaosValues
    $scope.selected = null
    $scope.selectedCev = 0
    $scope.desiredCev = 0
    $scope.rate =
      min: 0
      max: 10
      step: 1
      start: 5

    $scope.select = ->
      return unless chaosValues[$scope.selected]?
      $scope.selectedCev = parseFloat(chaosValues[$scope.selected].toFixed(2))
      console.log $scope.selectedCev

    primus.$on 'data', (data) ->
      # todo: send to service
      console.dir data

    return
  ]
  .controller 'PricingCtrl', ['$scope', 'searchService', ($scope, searchService) ->
    $scope.searchPhrase = ''
    $scope.percentiles = [ 5, 15, 50, 90 ]
    $scope.items = []
    $scope.search = ->
      searchService.search(
        index: 'index'
        size: 50
        sort: [
          'shop.chaosEquiv'
        ]
        body:
          query:
            filtered:
              query:
                match_phrase:
                  { 'info.tokenized.fullName': $scope.searchPhrase }
              filter:
                bool:
                  must: [
                    { term: { 'attributes.lockedToCharacter': 'no' } }
                    { term: { 'attributes.league': 'Perandus' } }
                    { term: { 'shop.hasPrice': 'yes' } }
                    { term: { 'attributes.rarity': 'Unique' } }
                    { range: { 'shop.chaosEquiv': { 'gt': 0 } } }
                  ]
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
      ).then (data) ->
        $scope.items =
          {
            id: row._source.uuid
            name: row._source.info.fullName
            icon: row._source.info.icon
            price: row._source.shop.chaosEquiv
          } for row in data.hits.hits
        ###$scope.items = []
        for nameBucket in data.aggregations.name.buckets
          $scope.items.push
            name: nameBucket.key
            currencies: ({
              name: currencyBucket.key
              prices: currencyBucket.price.values
            } for currencyBucket in nameBucket.currency.buckets)###
      , (err) ->
        console.error err

    return
  ]
  .controller 'ErrorCtrl', ['$rootScope', '$scope', ($rootScope, $scope) ->
    $scope.error =
      code: $rootScope.error?.code ? 500
      message: $rootScope.error?.message ? 'Unknown error!'
    return
  ]