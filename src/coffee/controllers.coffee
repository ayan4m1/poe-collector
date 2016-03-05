angular
  .module 'poe.controllers', [ 'poe.services' ]
  .controller 'HomeCtrl', ['$scope', ($scope) ->

  ]
  .controller 'ErrorCtrl', ['$rootScope', '$scope', ($rootScope, $scope) ->
    $scope.error =
      code: $rootScope.error?.code ? 500
      message: $rootScope.error?.message ? 'Unknown error!'

    return
  ]