config = require('konfig')()

util = require 'util'
gulp = require 'gulp'
sass = require 'gulp-sass'
gulpif = require 'gulp-if'
concat = require 'gulp-concat'
coffee = require 'gulp-coffee'
uglify = require 'gulp-uglify'
forever = require 'gulp-forever-monitor'

# ws lib generation
gulpFile = require 'gulp-file'
Primus = require 'primus'
primus = Primus.createServer({ port: 8080, transformer: 'faye' })
primus.destroy()

# return glob for source files by extension
srcGlob = (exts) ->
  return "src/#{exts}/**/*.#{exts}" unless util.isArray(exts)
  exts.map (ext) -> "src/#{ext}/**/*.#{ext}"

gulp.task 'update', -> [
# icon font
  gulp.src("lib/fontawesome/fonts/*").pipe(gulp.dest("www/fonts"))

# images
  gulp.src("src/img/**/*.{png,jpg,gif}").pipe(gulp.dest("www/img"))

# css
  gulp.src(srcGlob('scss'))
  .pipe(gulpif(/\.scss$/, sass()))
  .pipe(concat('main.css'))
  .pipe(gulp.dest("www/css"))

# js libs
  gulp.src [
    'lib/primus/'
    'lib/momentjs/moment.js'
    'lib/angular/angular.js'
    'lib/angular-route/angular-route.js'
    'lib/jquery/dist/jquery.js'
    'lib/bootstrap/dist/js/bootstrap.js' # must be included after jQuery
    'lib/ngstorage/ngStorage.js'
    'lib/angular-bootstrap/ui-bootstrap-tpls.js'
    'lib/angular-toastr/dist/angular-toastr.tpls.js'
    'lib/angular-primus/angular-primus.js'
  ]
  .pipe(gulpFile('primus.js', primus.library()))
  .pipe(concat('libs.js'))
  .pipe(gulpif(config.build.minify, uglify()))
  .pipe(gulp.dest("www/js"))

# coffee
  gulp.src(srcGlob('coffee'))
  .pipe(coffee())
  .pipe(concat('app.js'))
  .pipe(gulpif(config.build.minify, uglify()))
  .pipe(gulp.dest("www/js"))

# html
  gulp.src(srcGlob('html')).pipe(gulp.dest('www/'))
]

runScript = (path) ->
  forever path,
    command: 'coffee'
    watchIgnorePatterns: [
      '.git/'
      'node_modules/*'
      'lib/*'
    ]
    watch: true
    watchDirectory: 'bin/'
    # delay prevents churning due to rapid changes
    delay: config.build.watchInterval
    env: process.env
    #tasks: ['update']

gulp.task 'default', ['update'], ->
  runScript('bin/start-web.coffee')
  runScript('bin/start-watcher.coffee')

gulp.task 'clean', (done) -> require('rimraf')('www/', done)