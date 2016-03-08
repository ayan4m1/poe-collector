angular
  .module 'poe.directives', [ 'poe.services' ]
  .directive 'header', ->
    restrict: 'E'
    templateUrl: 'components/header.html'
  .directive 'navBar', ->
    restrict: 'A'
    templateUrl: 'components/nav-bar.html'
  .directive 'socketStatus', ['$rootScope', ($rootScope) ->
    restrict: 'A'
    template: '<i class="fa fa-fw fa-unlink"></i>'
    link: (scope, elem) ->
      icon = elem.find('i')
      $rootScope.$on 'watcher:opened', ->
        icon.addClass('fa-link').removeClass('fa-unlink')
      $rootScope.$on 'watcher:closed', ->
        icon.removeClass('fa-link').addClass('fa-unlink')
  ]