angular
  .module 'poe.controllers', [ 'poe.constants', 'poe.services' ]
  .controller 'HomeCtrl', ['$scope', 'primus', 'chaosValues', ($scope, primus, chaosValues) ->
    $scope.currencies = []
    $scope.currencies.push(key) for key, value of chaosValues
    $scope.selectedCev = 0
    $scope.desiredCev = 0
    $scope.rate =
      min: 0
      max: 10
      step: 1
      start: 5
    $scope.select = ->
      return unless chaosValues[$scope.selected]?
      $scope.selectedCev = chaosValues[$scope.selected].toFixed(2)

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