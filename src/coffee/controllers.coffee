angular
  .module 'poe.controllers', [ 'poe.constants', 'poe.services' ]
  .controller 'HomeCtrl', ['$scope', 'primus', 'chaosValues', 'watchService', ($scope, primus, chaosValues, watchService) ->
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
  .controller 'SearchCtrl', ['$scope', 'searchService', ($scope, searchService) ->
    searchService.search(
      index: 'index'
      body:
        size: 100
        fields: [
          'info.name'
        ]
        query:
          bool:
            must:
              #term: { 'attributes.lockedToCharacter': { value: false } }
              term: { 'attributes.league': { value: 'Perandus' } }
    ).then (data) ->
      console.dir data?.hits?.hits
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