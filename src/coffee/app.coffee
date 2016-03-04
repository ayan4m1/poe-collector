angular
  .module 'poe', [
    # external dependencies
    'ngRoute'
    'ui.bootstrap'

    # app modules
    'poe.controllers'
    'poe.directives'
    'poe.services'
  ]
  .config ['$routeProvider', '$locationProvider', '$httpProvider', ($routeProvider, $locationProvider, $httpProvider) ->
    # use history.pushState instead of hash-based routing
    $locationProvider.html5Mode(true)

    # todo: improve routing, reduce boilerplate
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
    .otherwise '/error'
  ]