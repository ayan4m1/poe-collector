'use strict';

const webpack = require('webpack');
const path = require('path');
const HtmlWebpackPlugin = require('html-webpack-plugin');
const ExtractTextWebpackPlugin = require('extract-text-webpack-plugin');

module.exports = {
  devtool: 'eval-source-map',
  entry: {
    'app': './src/ts/main.ts',
    'vendor': './src/ts/vendor.ts',
    'polyfills': './src/ts/polyfills.ts'
  },
  resolve: {
    extensions: ['.ts', '.js', '.json', '.css', '.scss', '.html']
  },
  output: {
    path: path.resolve(__dirname, 'build'),
    filename: '[name].js'
  },
  module: {
    rules: [
      {
        test: /\.ts$/,
        use: ['ts-loader', 'angular2-template-loader'],
        exclude: [/node_modules\/(?!(ng2-.+))/]
      },
      {test: /\.html$/, use: 'html-loader'},
      {test: /\.json$/, use: 'json-loader'},
      {
        test: /\.(png|jpe?g|gif|ico)$/,
        use: 'file-loader?name=assets/[name].[hash].[ext]'
      },
      {
        test: /\.css$/,
        exclude: path.resolve(__dirname, 'src/ts'),
        loader: ExtractTextWebpackPlugin.extract({ fallback: 'style-loader', use: ['css-loader', 'postcss-loader']})
      },
      {test: /\.css$/, include: path.resolve(__dirname, 'src/ts'), loader: 'raw-loader!postcss-loader'},
      {
        test: /\.(scss|sass)$/,
        exclude: path.resolve(__dirname, 'src/ts'),
        loader: ExtractTextWebpackPlugin.extract({ fallback: 'style-loader', use: ['css-loader', 'postcss-loader', 'sass-loader']})
      },
      {test: /\.(scss|sass)$/, exclude: path.resolve(__dirname, 'src/scss'), loader: 'raw-loader!postcss-loader!sass-loader'},
    ]
  },
  plugins: [
    new webpack.optimize.UglifyJsPlugin(),
    new webpack.optimize.CommonsChunkPlugin({
      name: ['app', 'vendor', 'polyfills']
    }),
    new HtmlWebpackPlugin({
      template: './src/html/index.html',
      chunksSortMode: 'dependency'
    }),
    new ExtractTextWebpackPlugin('style.css')
  ]
};
