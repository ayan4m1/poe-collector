angular
  .module 'poe.controllers', [ 'poe.constants', 'poe.services' ]
  .controller 'HomeCtrl', ['$scope', 'primus', 'chaosValues', ($scope, primus, chaosValues) ->
    $scope.currencies = []
    $scope.currencies.push(key) for key, value of chaosValues
    $scope.currentCev = '0'
    $scope.selectCurrency = ->
      return unless chaosValues[$scope.desiredCurrency]?
      $scope.currentCev = chaosValues[$scope.desiredCurrency].toFixed(2)

    primus.$on 'data', (data) ->
      # todo: send to service
      console.dir data
  ]
  .controller 'ErrorCtrl', ['$rootScope', '$scope', ($rootScope, $scope) ->
    $scope.error =
      code: $rootScope.error?.code ? 500
      message: $rootScope.error?.message ? 'Unknown error!'

    return
  ]