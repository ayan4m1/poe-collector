angular
  .module 'poe', [
    # external dependencies
    'primus'
    'ngRoute'
    'ui.bootstrap'
    'ui.bootstrap-slider'

    # app modules
    'poe.controllers'
    'poe.directives'
    'poe.services'
  ]
  .config ['$routeProvider', '$locationProvider', 'primusProvider', ($routeProvider, $locationProvider, primusProvider) ->
    # use history.pushState instead of hash-based routing
    $locationProvider.html5Mode(true)

    primusProvider.setEndpoint('http://localhost:3030')

    # todo: better routing scheme
    $routeProvider
    .when '/',
      templateUrl: 'partials/home.html'
      controller: 'HomeCtrl'
    .when '/search',
      templateUrl: 'partials/search.html'
      controller: 'SearchCtrl'
    .when '/error',
      templateUrl: 'partials/error.html'
      controller: 'ErrorCtrl'
    .otherwise
      redirectTo: ->
        # todo: get to rootScope.error here
        ###rootScope.error =
          code: 404
          message: 'Ugh'###

        return '/error'
  ]