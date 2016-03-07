angular.module 'poe.services', ['poe.constants', 'ngStorage']
# expose moment as a service for in-angular access and mocking
.factory 'moment', ['$window', ($window) -> $window.moment]
# watch socket events
.service 'socketService', ['primus', (primus) ->
  console.log primus
]