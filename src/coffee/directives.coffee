angular
  .module 'poe.directives', [ 'poe.services' ]
  .directive 'header', ->
    restrict: 'E'
    templateUrl: 'components/header.html'
  .directive 'navBar', ->
    restrict: 'A'
    templateUrl: 'components/nav-bar.html'
  .directive 'socketStatus', ['SocketService', (SocketService) ->
    restrict: 'A'
    template: '<i class="fa fa-fw fa-unlink"></i>'
    link: (scope, elem) ->
      icon = elem.find('i')
      SocketService.attach scope, 'watcher:opened', ->
        icon.addClass('fa-link').removeClass('fa-unlink')
      SocketService.attach scope, 'watcher:closed', ->
        icon.removeClass('fa-link').addClass('fa-unlink')
  ]
  .directive 'pricingRow', ->
    restrict: 'A'
    templateUrl: 'components/pricing-row.html'
    scope:
      item: '='
  .directive 'currencyRow', ->
    restrict: 'A'
    templateUrl: 'components/currency-row.html'
    scope:
      currency: '='