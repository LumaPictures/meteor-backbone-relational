Backbone.Models.Thread = Backbone.RelationalModel.extend
	urlRoot: "/api/Thread"
	idAttribute: "_id"
	relations: [{
		type: Backbone.HasMany
		key: "messages"
		relatedModel: "Message"
		reverseRelation:
			key: "thread"
			includeInJson: "_id"
	}]

Collections.Threads = new Meteor.Collection "threads"

@createThread = -> ( title, messages = [] ) ->
	Match.test title, String
	Match.test messages, Array
	Collections.Threads.insert
		title: title
		messages: messages

Backbone.Collections.ThreadList = Backbone.Collection.extend
	url: '/api/Thread'
	model: "Thread"