Tinytest.add "backbone-relational - definition", ( test ) ->
  test.notEqual Backbone, undefined, "Backbone should be defined on the client and server."
  test.notEqual Backbone.Relational, undefined, "Backbone.Relational should be defined on the client and server."
  test.notEqual Backbone.Relational.store, undefined, "Backbone.Relational.store should be defined on the client and server."
  test.notEqual Backbone.Models, undefined, "Models should be defined on the client and server."
  test.notEqual Backbone.Collections, undefined, "Collections should be defined on the client and server."

