angular
  .module 'poe.directives', []
  .directive 'header', ->
    restrict: 'E'
    templateUrl: 'components/header.html'
  .directive 'navBar', ->
    restrict: 'A'
    templateUrl: 'components/nav-bar.html'