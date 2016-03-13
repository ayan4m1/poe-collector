angular
  .module 'poe.controllers', [ 'poe.constants', 'poe.services' ]
  .controller 'CurrencyCtrl', ['$scope', 'SearchService', 'SocketService', 'chaosValues',
  ($scope, SearchService, SocketService, chaosValues) ->
    SocketService.attach $scope, 'watcher:item', (item) ->
      # notify if we care about it
      console.dir item

    $scope.currencies = []
    #$scope.currencies.push(key) for key, value of chaosValues
    SearchService.getCurrencyTrades().then (data) ->
      $scope.currencies = ({
        name: currency.key
        count: currency.doc_count
        stats: currency.priceStats
        percentiles: currency.pricePercentiles
      } for currency in data.aggregations.name.buckets)

      # todo: anything other than this
      ###for currency in $scope.currencies
        for row in data.hits.hits
          if row._source.info.name is currency.name
            currency.icon = row._source.info.icon
            break###

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

    return
  ]
  .controller 'PricingCtrl', ['$scope', 'SearchService', 'usSpinnerService',
  ($scope, SearchService, usSpinnerService) ->
    $scope.searchPhrase = ''

    $scope.items = []
    $scope.range = []

    $scope.search = null

    $scope.init = ->
      SearchService.getCurrencies().then (currencies) ->
        console.dir currencies

    $scope.reload = ->
      usSpinnerService.spin('search')
      $scope.search = SearchService.getItem { name: $scope.searchPhrase }

      $scope.search.then (data) ->
        usSpinnerService.stop('search')

        $scope.items = ({
          id: row._id
          name: row._source.info.fullName
          icon: row._source.info.icon
          price: row._source.shop.chaosEquiv
          rawPrice: "#{row._source.shop.amount} #{row._source.shop.currency}"
          mods: key.replace('#', value) for key, value of row._source.modsTotal
        } for row in data.hits.hits when row._id?)

        ###$scope.range = ({
          name: bucket.key
          average: bucket.price.values['15.0'] # 15th percentile
          count: bucket.doc_count
          percentiles: bucket.price.values
        } for bucket in data.aggregations.currency.buckets)###

        total = 0
        total += currency.count for currency in $scope.range
        $scope.totalListings = total
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