'use strict';

var config = require('konfig')(),
    gulp = require('gulp'),
    tsify = require('tsify'),
    gulpIf = require('gulp-if'),
    file = require('gulp-file'),
    sass = require('gulp-sass'),
    util = require('gulp-util'),
    ts = require('gulp-typescript'),
    concat = require('gulp-concat'),
    uglify = require('gulp-uglify'),
    buffer = require('vinyl-buffer'),
    typeLint = require('gulp-tslint'),
    nodemon = require('gulp-nodemon'),
    browserify = require('browserify'),
    source = require('vinyl-source-stream');

var out = "www/";

var browserifier = browserify()
      .add('src/ts/main.ts')
      .plugin(tsify, {
        project: 'config/'
      });

gulp.task('update', [], function () { return [
  gulp.src('lib/fontawesome/fonts/*')
  .pipe(gulp.dest(out + 'fonts')),

  gulp.src('src/img/**/*.{png,jpg,gif}')
  .pipe(gulp.dest(out + 'img')),

  gulp.src([
    'src/scss/**/*.scss',
    'lib/seiyria-bootstrap-slider/dist/css/bootstrap-slider.css'
  ])
    .pipe(gulpIf(/\.scss$/, sass()))
    .pipe(concat('main.css'))
  .pipe(gulp.dest(out + 'css')),

  gulp.src([
    'lib/momentjs/moment.js',
    'lib/jquery/dist/jquery.js',
    'lib/bootstrap/dist/js/bootstrap.js' // must be included after jQuery
  ])
    .pipe(concat('libs.js'))
    .pipe(gulpIf(config.build.minify, uglify()))
  .pipe(gulp.dest(out + 'js')),

  browserifier.bundle()
    .pipe(source('app.js'))
    .pipe(gulpIf(config.build.minify, uglify()))
  .pipe(gulp.dest(out + 'js')),

  gulp.src('src/html/**/*.html')
  .pipe(gulp.dest(out))
]; });

gulp.task('default', [ 'update' ], function () {
  runScript('bin/start-web.coffee')
});

var runScript = function (path) { 
  return nodemon({
    script: path,
    ignore: [
      '.git/',
      'node_modules/',
      'lib/'
    ],
    watch: [
      'bin/',
      'src/'
    ],
    ext: 'ts html scss',
    delay: config.build.watchInterval,
    env: process.env,
    tasks: [ 'update' ]
  });
}
