Backbone.Models.Message = Backbone.RelationalModel.extend
	urlRoot: '/api/Message'
	idAttribute: '_id'

Collections.Messages = new Meteor.Collection "messages"

@createMessage = ( author, text, thread ) ->
	Match.test author, String
	Match.test text, String
	Match.test thread, String
	Collections.Messages.insert
		author: author
		text: text
		thread: thread