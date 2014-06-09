Backbone.Models = {}
Backbone.Collections = {}

if Meteor.isClient
	scope = window
if Meteor.isServer
	scope = root
	
Backbone.Relational.store.removeModelScope scope
Backbone.Relational.store.addModelScope Backbone.Models