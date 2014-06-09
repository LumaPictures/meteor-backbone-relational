Package.describe({
  summary: "Client and Server models for handling relational data."
});

Package.on_use(function (api, where) {
  api.use([
    'coffeescript',
    'underscore'
  ],[ 'client', 'server' ]);

  api.use([
    'jquery'
  ], [ 'client' ]);

  api.export([
    "Backbone",
    "Models",
    "Collections"
  ], ['client','server']);

  api.add_files([
    'lib/backbone.js',
    'lib/backbone.relational.js',
    'lib/backbone.scopes.coffee'
  ], [ 'client', 'server' ]);
});

Package.on_test(function (api) {
  api.use([
    'coffeescript',
    'backbone-relational',
    'tinytest',
    'test-helpers'
  ], ['client', 'server']);

  api.add_files([
    'tests/backbone-relational.test.coffee'
  ], ['client', 'server']);
});