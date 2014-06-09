Package.describe({
  summary: "Client and Server models for handling relational data."
});

Package.on_use(function (api, where) {
  api.use([
    'coffeescript',
    'underscore'
  ],[ 'client', 'server' ]);

  api.export([
    "Backbone",
    "Models",
    "Collections"
  ], ['client','server']);

  api.add_files([
    'lib/backbone.coffee',
    'lib/backbone.relational.coffee',
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