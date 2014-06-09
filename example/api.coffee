Router.map ->
	@route 'put_a_model_instance',
		path: '/api/:model'
		where: 'server'
		action: ->
			router = @
			body = router.request.body
			model = router.params.model
			method = router.request.method
			collection = "#{ model }s"
			url = router.request.url

			Match.test model, String
			Match.test body, Object
			Match.test method, String
			Match.test url, String
			Match.test collection, String

			request_id = "#{ url }:#{ method }"
			console.log "#{ request_id }:model", model
			console.log "#{ request_id }:collection", collection
			console.log "#{ request_id }:request:body", body

			if method is "POST"
				if Collections[ collection ]
					result = Collections[ collection ].upsert _id: body._id, body
					throw new Error "Model Instance #{ body._id } not found." unless result.numberAffected
					body._id = result.insertedId if result.insertedId
					router.response.writeHead 200, { 'Content-type': 'application/json' }
					router.response.end JSON.stringify( body )
				else throw new Error "Model not defined", model

  @route 'get_a_model_instance',
		path: '/api/:model/:_id'
		where: 'server'
		action: ->
			router = @

			Match.test router.params.model, String
			Match.test router.params._id, Number

			console.log "get:method", router.request.method
			console.log "get:model", router.params.model
			console.log "get:_id", router.params._id

			if Models[ router.params.model ]
			  modelClass = Models[ router.params.model ]
			  console.log "get:modelClass", modelClass
			else throw new Error "Model not defined", router.params.model

			fetchModel = 
				error: true

			unless fetchModel.error
			  router.response.writeHead 200, 'Content-type': 'application/json'
			  router.response.end JSON.stringify fetchModel.result.toJSON()