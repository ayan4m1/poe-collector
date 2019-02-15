import del from 'del';
import gulp from 'gulp';
import babel from 'gulp-babel';
import eslint from 'gulp-eslint';
import nodemon from 'gulp-nodemon';

const src = './src/**/*.js';
const dst = './lib/';

const develop = done => {
  nodemon({
    tasks: ['build'],
    ignore: ['lib/'],
    script: 'lib/index.js',
    ext: 'js',
    delay: 2000,
    done
  });
};

const lint = () =>
  gulp
    .src(src)
    .pipe(eslint())
    .pipe(eslint.format())
    .pipe(eslint.failAfterError());

const build = () =>
  gulp
    .src(src)
    .pipe(babel())
    .pipe(gulp.dest(dst));

const clean = () => del(dst);
const watch = () => gulp.watch(src, build);

gulp.task('lint', lint);
gulp.task('build', build);
gulp.task('clean', clean);
gulp.task('watch', gulp.series(build, watch));
gulp.task('default', gulp.series(clean, lint, build));
gulp.task('develop', gulp.series(clean, lint, build, develop));
