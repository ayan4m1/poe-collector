angular
  .module 'poe', [
    # ui deps
    'ui.bootstrap'
    'ui.bootstrap-slider'
    'angularSpinner'
    'toastr'

    # libs
    'primus'
    'ngRoute'
    'ngAnimate'
    'elasticsearch'

    # app modules
    'poe.controllers'
    'poe.constants'
    'poe.directives'
    'poe.services'
  ]
  .config ['$routeProvider', '$locationProvider', 'primusProvider', 'socketUri', ($routeProvider, $locationProvider, primusProvider, socketUri) ->
    # use history.pushState instead of hash-based routing
    $locationProvider.html5Mode true

    # pull WS config from constants
    primusProvider.setEndpoint socketUri

    # todo: better routing scheme
    $routeProvider
    .when '/',
      templateUrl: 'partials/home.html'
    .when '/currency',
      templateUrl: 'partials/currency.html'
      controller: 'CurrencyCtrl'
    .when '/pricing',
      templateUrl: 'partials/pricing.html'
      controller: 'PricingCtrl'
    .when '/error',
      templateUrl: 'partials/error.html'
      controller: 'ErrorCtrl'
    .otherwise { redirectTo: -> '/' }
  ]