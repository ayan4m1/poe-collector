config = require('konfig')()

util = require 'util'
gulp = require 'gulp'
sass = require 'gulp-sass'
gulpIf = require 'gulp-if'
gulpFile = require 'gulp-file'
concat = require 'gulp-concat'
coffee = require 'gulp-coffee'
uglify = require 'gulp-uglify'
nodemon = require 'gulp-nodemon'
ts = require 'gulp-typescript'

# ws lib generation, ugly!
Primus = require 'primus'
primus = Primus.createServer({ port: 8080, transformer: 'faye' })
primus.destroy()

# return glob for source files by extension
srcGlob = (exts) ->
  return "src/#{exts}/**/*.#{exts}" unless util.isArray(exts)
  exts.map (ext) -> "src/#{ext}/**/*.#{ext}"

typeScript = ts.createProject 'config/tsconfig.json'
typeLint = require 'gulp-tslint'

gulp.task 'update', -> [
# icon font
  gulp.src("lib/fontawesome/fonts/*").pipe(gulp.dest("www/fonts"))

# images
  gulp.src("src/img/**/*.{png,jpg,gif}").pipe(gulp.dest("www/img"))

# css
  gulp.src([
    srcGlob('scss')
    'lib/seiyria-bootstrap-slider/dist/css/bootstrap-slider.css'
    'lib/angular-toastr/dist/angular-toastr.css'
  ])
  .pipe(gulpIf(/\.scss$/, sass()))
  .pipe(concat('main.css'))
  .pipe(gulp.dest("www/css"))

# js libs
  gulp.src [
    'lib/momentjs/moment.js'
    'lib/jquery/dist/jquery.js'
    'lib/bootstrap/dist/js/bootstrap.js' # must be included after jQuery
  ]
  .pipe(gulpFile('primus.js', primus.library()))
  .pipe(concat('libs.js'))
  .pipe(gulpIf(config.build.minify, uglify()))
  .pipe(gulp.dest("www/js"))

# typescript
  gulp.src(srcGlob('ts'))
  .pipe(typeScript())
  .pipe(concat('app.js'))
  .pipe(gulpIf(config.build.minify, uglify()))
  .pipe(gulp.dest("www/js"))

# html
  gulp.src(srcGlob('html')).pipe(gulp.dest('www/'))
]

gulp.task 'lint', -> [
  gulp.src(srcGlob('ts'))
  .pipe(typeLint(
    configuration: 'config/tslint.json'
  ))
  .pipe(typeLint.report())
]

runScript = (path) ->
  nodemon
    script: path
    ignore: [
      '.git/'
      'node_modules/*'
      'lib/*'
    ]
    watch: [
      'bin/'
      'src/'
    ]
    ext: 'coffee html scss'
    # delay prevents churning due to rapid changes
    delay: config.build.watchInterval
    env: process.env
    tasks: ['update']

gulp.task 'default', ['update'], -> runScript('bin/start-web.coffee')
gulp.task 'clean', (done) -> require('rimraf')('www/', done)
