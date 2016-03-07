angular
  .module 'poe.directives', [ 'poe.services' ]
  .directive 'header', ->
    restrict: 'E'
    templateUrl: 'components/header.html'
  .directive 'navBar', ->
    restrict: 'A'
    templateUrl: 'components/nav-bar.html'
  .directive 'socketState', ['socketService', ->
    restrict: 'A'
    link: (scope) ->
      scope.active = -> true
  ]