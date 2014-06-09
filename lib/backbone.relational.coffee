# vim: set tabstop=4 softtabstop=4 shiftwidth=4 noexpandtab: 

###
Backbone-relational.js 0.8.8
(c) 2011-2014 Paul Uithol and contributors (https://github.com/PaulUithol/Backbone-relational/graphs/contributors)

Backbone-relational may be freely distributed under the MIT license; see the accompanying LICENSE.txt.
For details and documentation: https://github.com/PaulUithol/Backbone-relational.
Depends on Backbone (and thus on Underscore as well): https://github.com/documentcloud/backbone.

Example:

Zoo = Backbone.RelationalModel.extend({
relations: [ {
type: Backbone.HasMany,
key: 'animals',
relatedModel: 'Animal',
reverseRelation: {
key: 'livesIn',
includeInJSON: 'id'
// 'relatedModel' is automatically set to 'Zoo'; the 'relationType' to 'HasOne'.
}
} ],

toString: function() {
return this.get( 'name' );
}
});

Animal = Backbone.RelationalModel.extend({
toString: function() {
return this.get( 'species' );
}
});

// Creating the zoo will give it a collection with one animal in it: the monkey.
// The animal created after that has a relation `livesIn` that points to the zoo it's currently associated with.
// If you instantiate (or fetch) the zebra later, it will automatically be added.

var zoo = new Zoo({
name: 'Artis',
animals: [ { id: 'monkey-1', species: 'Chimp' }, 'lion-1', 'zebra-1' ]
});

var lion = new Animal( { id: 'lion-1', species: 'Lion' } ),
monkey = zoo.get( 'animals' ).first(),
sameZoo = lion.get( 'livesIn' );
###

Backbone.Relational = showWarnings: true

###
Semaphore mixin; can be used as both binary and counting.
###
Backbone.Semaphore =
  _permitsAvailable: null
  _permitsUsed: 0
  acquire: ->
    if @_permitsAvailable and @_permitsUsed >= @_permitsAvailable
      throw new Error("Max permits acquired")
    else
      @_permitsUsed++
    return

  release: ->
    if @_permitsUsed is 0
      throw new Error("All permits released")
    else
      @_permitsUsed--
    return

  isLocked: ->
    @_permitsUsed > 0

  setAvailablePermits: (amount) ->
    throw new Error("Available permits cannot be less than used permits")  if @_permitsUsed > amount
    @_permitsAvailable = amount
    return


###
A BlockingQueue that accumulates items while blocked (via 'block'),
and processes them when unblocked (via 'unblock').
Process can also be called manually (via 'process').
###
Backbone.BlockingQueue = ->
  @_queue = []
  return

_.extend Backbone.BlockingQueue::, Backbone.Semaphore,
  _queue: null
  add: (func) ->
    if @isBlocked()
      @_queue.push func
    else
      func()
    return

  
  # Some of the queued events may trigger other blocking events. By
  # copying the queue here it allows queued events to process closer to
  # the natural order.
  #
  # queue events [ 'A', 'B', 'C' ]
  # A handler of 'B' triggers 'D' and 'E'
  # By copying `this._queue` this executes:
  # [ 'A', 'B', 'D', 'E', 'C' ]
  # The same order the would have executed if they didn't have to be
  # delayed and queued.
  process: ->
    queue = @_queue
    @_queue = []
    queue.shift()()  while queue and queue.length
    return

  block: ->
    @acquire()
    return

  unblock: ->
    @release()
    @process()  unless @isBlocked()
    return

  isBlocked: ->
    @isLocked()


###
Global event queue. Accumulates external events ('add:<key>', 'remove:<key>' and 'change:<key>')
until the top-level object is fully initialized (see 'Backbone.RelationalModel').
###
Backbone.Relational.eventQueue = new Backbone.BlockingQueue()

###
Backbone.Store keeps track of all created (and destruction of) Backbone.RelationalModel.
Handles lookup for relations.
###
Backbone.Store = ->
  @_collections = []
  @_reverseRelations = []
  @_orphanRelations = []
  @_subModels = []
  @_modelScopes = [ Backbone.Relational ]
  return

_.extend Backbone.Store::, Backbone.Events,
  
  ###
  Create a new `Relation`.
  @param {Backbone.RelationalModel} [model]
  @param {Object} relation
  @param {Object} [options]
  ###
  initializeRelation: (model, relation, options) ->
    type = (if not _.isString(relation.type) then relation.type else Backbone[relation.type] or @getObjectByName(relation.type))
    if type and type:: instanceof Backbone.Relation
      rel = new type(model, relation, options) # Also pushes the new Relation into `model._relations`
    else
      Backbone.Relational.showWarnings and typeof console isnt "undefined" and console.warn("Relation=%o; missing or invalid relation type!", relation)
    return

  
  ###
  Add a scope for `getObjectByName` to look for model types by name.
  @param {Object} scope
  ###
  addModelScope: (scope) ->
    @_modelScopes.push scope
    return

  
  ###
  Remove a scope.
  @param {Object} scope
  ###
  removeModelScope: (scope) ->
    @_modelScopes = _.without(@_modelScopes, scope)
    return

  
  ###
  Add a set of subModelTypes to the store, that can be used to resolve the '_superModel'
  for a model later in 'setupSuperModel'.
  
  @param {Backbone.RelationalModel} subModelTypes
  @param {Backbone.RelationalModel} superModelType
  ###
  addSubModels: (subModelTypes, superModelType) ->
    @_subModels.push
      superModelType: superModelType
      subModels: subModelTypes

    return

  
  ###
  Check if the given modelType is registered as another model's subModel. If so, add it to the super model's
  '_subModels', and set the modelType's '_superModel', '_subModelTypeName', and '_subModelTypeAttribute'.
  
  @param {Backbone.RelationalModel} modelType
  ###
  setupSuperModel: (modelType) ->
    _.find @_subModels, ((subModelDef) ->
      
      # Set 'modelType' as a child of the found superModel
      
      # Set '_superModel', '_subModelTypeValue', and '_subModelTypeAttribute' on 'modelType'.
      _.filter(subModelDef.subModels or [], (subModelTypeName, typeValue) ->
        subModelType = @getObjectByName(subModelTypeName)
        if modelType is subModelType
          subModelDef.superModelType._subModels[typeValue] = modelType
          modelType._superModel = subModelDef.superModelType
          modelType._subModelTypeValue = typeValue
          modelType._subModelTypeAttribute = subModelDef.superModelType::subModelTypeAttribute
          true
      , this).length
    ), this
    return

  
  ###
  Add a reverse relation. Is added to the 'relations' property on model's prototype, and to
  existing instances of 'model' in the store as well.
  @param {Object} relation
  @param {Backbone.RelationalModel} relation.model
  @param {String} relation.type
  @param {String} relation.key
  @param {String|Object} relation.relatedModel
  ###
  addReverseRelation: (relation) ->
    exists = _.any(@_reverseRelations, (rel) ->
      _.all relation or [], (val, key) ->
        val is rel[key]

    )
    if not exists and relation.model and relation.type
      @_reverseRelations.push relation
      @_addRelation relation.model, relation
      @retroFitRelation relation
    return

  
  ###
  Deposit a `relation` for which the `relatedModel` can't be resolved at the moment.
  
  @param {Object} relation
  ###
  addOrphanRelation: (relation) ->
    exists = _.any(@_orphanRelations, (rel) ->
      _.all relation or [], (val, key) ->
        val is rel[key]

    )
    @_orphanRelations.push relation  if not exists and relation.model and relation.type
    return

  
  ###
  Try to initialize any `_orphanRelation`s
  ###
  processOrphanRelations: ->
    
    # Make sure to operate on a copy since we're removing while iterating
    _.each @_orphanRelations.slice(0), ((rel) ->
      relatedModel = Backbone.Relational.store.getObjectByName(rel.relatedModel)
      if relatedModel
        @initializeRelation null, rel
        @_orphanRelations = _.without(@_orphanRelations, rel)
      return
    ), this
    return

  
  ###
  @param {Backbone.RelationalModel.constructor} type
  @param {Object} relation
  @private
  ###
  _addRelation: (type, relation) ->
    type::relations = []  unless type::relations
    type::relations.push relation
    _.each type._subModels or [], ((subModel) ->
      @_addRelation subModel, relation
      return
    ), this
    return

  
  ###
  Add a 'relation' to all existing instances of 'relation.model' in the store
  @param {Object} relation
  ###
  retroFitRelation: (relation) ->
    coll = @getCollection(relation.model, false)
    coll and coll.each((model) ->
      return  unless model instanceof relation.model
      rel = new relation.type(model, relation)
      return
    , this)
    return

  
  ###
  Find the Store's collection for a certain type of model.
  @param {Backbone.RelationalModel} type
  @param {Boolean} [create=true] Should a collection be created if none is found?
  @return {Backbone.Collection} A collection if found (or applicable for 'model'), or null
  ###
  getCollection: (type, create) ->
    type = type.constructor  if type instanceof Backbone.RelationalModel
    rootModel = type
    rootModel = rootModel._superModel  while rootModel._superModel
    coll = _.find(@_collections, (item) ->
      item.model is rootModel
    )
    coll = @_createCollection(rootModel)  if not coll and create isnt false
    coll

  
  ###
  Find a model type on one of the modelScopes by name. Names are split on dots.
  @param {String} name
  @return {Object}
  ###
  getObjectByName: (name) ->
    parts = name.split(".")
    type = null
    _.find @_modelScopes, ((scope) ->
      type = _.reduce(parts or [], (memo, val) ->
        (if memo then memo[val] else `undefined`)
      , scope)
      true  if type and type isnt scope
    ), this
    type

  _createCollection: (type) ->
    coll = undefined
    
    # If 'type' is an instance, take its constructor
    type = type.constructor if type instanceof Backbone.RelationalModel
    
    # Type should inherit from Backbone.RelationalModel.
    # REVIEW : CHRISL
    # Removed type check because it was preventing the model instance from being added to the collection
    #if type:: instanceof Backbone.RelationalModel
    coll = new Backbone.Collection()
    coll.model = type
    @_collections.push coll
    coll

  
  ###
  Find the attribute that is to be used as the `id` on a given object
  @param type
  @param {String|Number|Object|Backbone.RelationalModel} item
  @return {String|Number}
  ###
  resolveIdForItem: (type, item) ->
    id = (if _.isString(item) or _.isNumber(item) then item else null)
    if id is null
      if item instanceof Backbone.RelationalModel
        id = item.id
      else id = item[type::idAttribute]  if _.isObject(item)
    
    # Make all falsy values `null` (except for 0, which could be an id.. see '/issues/179')
    id = null  if not id and id isnt 0
    id

  
  ###
  Find a specific model of a certain `type` in the store
  @param type
  @param {String|Number|Object|Backbone.RelationalModel} item
  ###
  find: (type, item) ->
    id = @resolveIdForItem(type, item)
    coll = @getCollection(type)
    
    # Because the found object could be of any of the type's superModel
    # types, only return it if it's actually of the type asked for.
    if coll
      obj = coll.get(id)
      return obj  if obj instanceof type
    null

  
  ###
  Add a 'model' to its appropriate collection. Retain the original contents of 'model.collection'.
  @param {Backbone.RelationalModel} model
  ###
  register: (model) ->
    coll = @getCollection(model)
    if coll
      modelColl = model.collection
      coll.add model
      model.collection = modelColl
    return

  
  ###
  Check if the given model may use the given `id`
  @param model
  @param [id]
  ###
  checkId: (model, id) ->
    coll = @getCollection(model)
    duplicate = coll and coll.get(id)
    if duplicate and model isnt duplicate
      console.warn "Duplicate id! Old RelationalModel=%o, new RelationalModel=%o", duplicate, model  if Backbone.Relational.showWarnings and typeof console isnt "undefined"
      throw new Error("Cannot instantiate more than one Backbone.RelationalModel with the same id per type!")
    return

  
  ###
  Explicitly update a model's id in its store collection
  @param {Backbone.RelationalModel} model
  ###
  update: (model) ->
    coll = @getCollection(model)
    
    # Register a model if it isn't yet (which happens if it was created without an id).
    @register model  unless coll.contains(model)
    
    # This triggers updating the lookup indices kept in a collection
    coll._onModelEvent "change:" + model.idAttribute, model, coll
    
    # Trigger an event on model so related models (having the model's new id in their keyContents) can add it.
    model.trigger "relational:change:id", model, coll
    return

  
  ###
  Unregister from the store: a specific model, a collection, or a model type.
  @param {Backbone.RelationalModel|Backbone.RelationalModel.constructor|Backbone.Collection} type
  ###
  unregister: (type) ->
    coll = undefined
    models = undefined
    if type instanceof Backbone.Model
      coll = @getCollection(type)
      models = [type]
    else if type instanceof Backbone.Collection
      coll = @getCollection(type.model)
      models = _.clone(type.models)
    else
      coll = @getCollection(type)
      models = _.clone(coll.models)
    _.each models, ((model) ->
      @stopListening model
      _.invoke model.getRelations(), "stopListening"
      return
    ), this
    
    # If we've unregistered an entire store collection, reset the collection (which is much faster).
    # Otherwise, remove each model one by one.
    if _.contains(@_collections, type)
      coll.reset []
    else
      _.each models, ((model) ->
        if coll.get(model)
          coll.remove model
        else
          coll.trigger "relational:remove", model, coll
        return
      ), this
    return

  
  ###
  Reset the `store` to it's original state. The `reverseRelations` are kept though, since attempting to
  re-initialize these on models would lead to a large amount of warnings.
  ###
  reset: ->
    @stopListening()
    
    # Unregister each collection to remove event listeners
    _.each @_collections, ((coll) ->
      @unregister coll
      return
    ), this
    @_collections = []
    @_subModels = []
    @_modelScopes = [exports]
    return

Backbone.Relational.store = new Backbone.Store()

###
The main Relation class, from which 'HasOne' and 'HasMany' inherit. Internally, 'relational:<key>' events
are used to regulate addition and removal of models from relations.

@param {Backbone.RelationalModel} [instance] Model that this relation is created for. If no model is supplied,
Relation just tries to instantiate it's `reverseRelation` if specified, and bails out after that.
@param {Object} options
@param {string} options.key
@param {Backbone.RelationalModel.constructor} options.relatedModel
@param {Boolean|String} [options.includeInJSON=true] Serialize the given attribute for related model(s)' in toJSON, or just their ids.
@param {Boolean} [options.createModels=true] Create objects from the contents of keys if the object is not found in Backbone.store.
@param {Object} [options.reverseRelation] Specify a bi-directional relation. If provided, Relation will reciprocate
the relation to the 'relatedModel'. Required and optional properties match 'options', except that it also needs
{Backbone.Relation|String} type ('HasOne' or 'HasMany').
@param {Object} opts
###
Backbone.Relation = (instance, options, opts) ->
  @instance = instance
  
  # Make sure 'options' is sane, and fill with defaults from subclasses and this object's prototype
  options = (if _.isObject(options) then options else {})
  @reverseRelation = _.defaults(options.reverseRelation or {}, @options.reverseRelation)
  @options = _.defaults(options, @options, Backbone.Relation::options)
  @reverseRelation.type = (if not _.isString(@reverseRelation.type) then @reverseRelation.type else Backbone[@reverseRelation.type] or Backbone.Relational.store.getObjectByName(@reverseRelation.type))
  @key = @options.key
  @keySource = @options.keySource or @key
  @keyDestination = @options.keyDestination or @keySource or @key
  @model = @options.model or @instance.constructor
  @relatedModel = @options.relatedModel
  @relatedModel = _.result(this, "relatedModel")  if _.isFunction(@relatedModel) and (@relatedModel:: not instanceof Backbone.RelationalModel)
  @relatedModel = Backbone.Relational.store.getObjectByName(@relatedModel)  if _.isString(@relatedModel)
  return  unless @checkPreconditions()
  
  # Add the reverse relation on 'relatedModel' to the store's reverseRelations
  if not @options.isAutoRelation and @reverseRelation.type and @reverseRelation.key
    Backbone.Relational.store.addReverseRelation _.defaults(
      isAutoRelation: true
      model: @relatedModel
      relatedModel: @model
      reverseRelation: @options # current relation is the 'reverseRelation' for its own reverseRelation
    , @reverseRelation) # Take further properties from this.reverseRelation (type, key, etc.)
  if instance
    contentKey = @keySource
    contentKey = @key  if contentKey isnt @key and _.isObject(@instance.get(@key))
    @setKeyContents @instance.get(contentKey)
    @relatedCollection = Backbone.Relational.store.getCollection(@relatedModel)
    
    # Explicitly clear 'keySource', to prevent a leaky abstraction if 'keySource' differs from 'key'.
    delete @instance.attributes[@keySource]  if @keySource isnt @key
    
    # Add this Relation to instance._relations
    @instance._relations[@key] = this
    @initialize opts
    @instance.fetchRelated @key, (if _.isObject(@options.autoFetch) then @options.autoFetch else {})  if @options.autoFetch
    
    # When 'relatedModel' are created or destroyed, check if it affects this relation.
    @listenTo(@instance, "destroy", @destroy).listenTo(@relatedCollection, "relational:add relational:change:id", @tryAddRelated).listenTo @relatedCollection, "relational:remove", @removeRelated
  return


# Fix inheritance :\
Backbone.Relation.extend = Backbone.Model.extend

# Set up all inheritable **Backbone.Relation** properties and methods.
_.extend Backbone.Relation::, Backbone.Events, Backbone.Semaphore,
  options:
    createModels: true
    includeInJSON: true
    isAutoRelation: false
    autoFetch: false
    parse: false

  instance: null
  key: null
  keyContents: null
  relatedModel: null
  relatedCollection: null
  reverseRelation: null
  related: null
  
  ###
  Check several pre-conditions.
  @return {Boolean} True if pre-conditions are satisfied, false if they're not.
  ###
  checkPreconditions: ->
    i = @instance
    k = @key
    m = @model
    rm = @relatedModel
    warn = Backbone.Relational.showWarnings and typeof console isnt "undefined"
    if not m or not k or not rm
      warn and console.warn("Relation=%o: missing model, key or relatedModel (%o, %o, %o).", this, m, k, rm)
      return false
    
    # Check if the type in 'model' inherits from Backbone.RelationalModel
    unless m:: instanceof Backbone.RelationalModel
      warn and console.warn("Relation=%o: model does not inherit from Backbone.RelationalModel (%o).", this, i)
      return false
    
    # Check if the type in 'relatedModel' inherits from Backbone.RelationalModel
    unless rm:: instanceof Backbone.RelationalModel
      warn and console.warn("Relation=%o: relatedModel does not inherit from Backbone.RelationalModel (%o).", this, rm)
      return false
    
    # Check if this is not a HasMany, and the reverse relation is HasMany as well
    if this instanceof Backbone.HasMany and @reverseRelation.type is Backbone.HasMany
      warn and console.warn("Relation=%o: relation is a HasMany, and the reverseRelation is HasMany as well.", this)
      return false
    
    # Check if we're not attempting to create a relationship on a `key` that's already used.
    if i and _.keys(i._relations).length
      existing = _.find(i._relations, (rel) ->
        rel.key is k
      , this)
      if existing
        warn and console.warn("Cannot create relation=%o on %o for model=%o: already taken by relation=%o.", this, k, i, existing)
        return false
    true

  
  ###
  Set the related model(s) for this relation
  @param {Backbone.Model|Backbone.Collection} related
  ###
  setRelated: (related) ->
    @related = related
    @instance.attributes[@key] = related
    return

  
  ###
  Determine if a relation (on a different RelationalModel) is the reverse
  relation of the current one.
  @param {Backbone.Relation} relation
  @return {Boolean}
  ###
  _isReverseRelation: (relation) ->
    relation.instance instanceof @relatedModel and @reverseRelation.key is relation.key and @key is relation.reverseRelation.key

  
  ###
  Get the reverse relations (pointing back to 'this.key' on 'this.instance') for the currently related model(s).
  @param {Backbone.RelationalModel} [model] Get the reverse relations for a specific model.
  If not specified, 'this.related' is used.
  @return {Backbone.Relation[]}
  ###
  getReverseRelations: (model) ->
    reverseRelations = []
    
    # Iterate over 'model', 'this.related.models' (if this.related is a Backbone.Collection), or wrap 'this.related' in an array.
    models = (if not _.isUndefined(model) then [model] else @related and (@related.models or [@related]))
    _.each models or [], ((related) ->
      _.each related.getRelations() or [], ((relation) ->
        reverseRelations.push relation  if @_isReverseRelation(relation)
        return
      ), this
      return
    ), this
    reverseRelations

  
  ###
  When `this.instance` is destroyed, cleanup our relations.
  Get reverse relation, call removeRelated on each.
  ###
  destroy: ->
    @stopListening()
    if this instanceof Backbone.HasOne
      @setRelated null
    else @setRelated @_prepareCollection()  if this instanceof Backbone.HasMany
    _.each @getReverseRelations(), ((relation) ->
      relation.removeRelated @instance
      return
    ), this
    return

Backbone.HasOne = Backbone.Relation.extend(
  options:
    reverseRelation:
      type: "HasMany"

  initialize: (opts) ->
    @listenTo @instance, "relational:change:" + @key, @onChange
    related = @findRelated(opts)
    @setRelated related
    
    # Notify new 'related' object of the new relation.
    _.each @getReverseRelations(), ((relation) ->
      relation.addRelated @instance, opts
      return
    ), this
    return

  
  ###
  Find related Models.
  @param {Object} [options]
  @return {Backbone.Model}
  ###
  findRelated: (options) ->
    related = null
    options = _.defaults(
      parse: @options.parse
    , options)
    if @keyContents instanceof @relatedModel
      related = @keyContents
    else if @keyContents or @keyContents is 0 # since 0 can be a valid `id` as well
      opts = _.defaults(
        create: @options.createModels
      , options)
      related = @relatedModel.findOrCreate(@keyContents, opts)
    
    # Nullify `keyId` if we have a related model; in case it was already part of the relation
    @keyId = null  if related
    related

  
  ###
  Normalize and reduce `keyContents` to an `id`, for easier comparison
  @param {String|Number|Backbone.Model} keyContents
  ###
  setKeyContents: (keyContents) ->
    @keyContents = keyContents
    @keyId = Backbone.Relational.store.resolveIdForItem(@relatedModel, @keyContents)
    return

  
  ###
  Event handler for `change:<key>`.
  If the key is changed, notify old & new reverse relations and initialize the new relation.
  ###
  onChange: (model, attr, options) ->
    
    # Don't accept recursive calls to onChange (like onChange->findRelated->findOrCreate->initializeRelations->addRelated->onChange)
    return  if @isLocked()
    @acquire()
    options = (if options then _.clone(options) else {})
    
    # 'options.__related' is set by 'addRelated'/'removeRelated'. If it is set, the change
    # is the result of a call from a relation. If it's not, the change is the result of
    # a 'set' call on this.instance.
    changed = _.isUndefined(options.__related)
    oldRelated = (if changed then @related else options.__related)
    if changed
      @setKeyContents attr
      related = @findRelated(options)
      @setRelated related
    
    # Notify old 'related' object of the terminated relation
    if oldRelated and @related isnt oldRelated
      _.each @getReverseRelations(oldRelated), ((relation) ->
        relation.removeRelated @instance, null, options
        return
      ), this
    
    # Notify new 'related' object of the new relation. Note we do re-apply even if this.related is oldRelated;
    # that can be necessary for bi-directional relations if 'this.instance' was created after 'this.related'.
    # In that case, 'this.instance' will already know 'this.related', but the reverse might not exist yet.
    _.each @getReverseRelations(), ((relation) ->
      relation.addRelated @instance, options
      return
    ), this
    
    # Fire the 'change:<key>' event if 'related' was updated
    if not options.silent and @related isnt oldRelated
      dit = this
      @changed = true
      Backbone.Relational.eventQueue.add ->
        dit.instance.trigger "change:" + dit.key, dit.instance, dit.related, options, true
        dit.changed = false
        return

    @release()
    return

  
  ###
  If a new 'this.relatedModel' appears in the 'store', try to match it to the last set 'keyContents'
  ###
  tryAddRelated: (model, coll, options) ->
    if (@keyId or @keyId is 0) and model.id is @keyId # since 0 can be a valid `id` as well
      @addRelated model, options
      @keyId = null
    return

  addRelated: (model, options) ->
    
    # Allow 'model' to set up its relations before proceeding.
    # (which can result in a call to 'addRelated' from a relation of 'model')
    dit = this
    model.queue ->
      if model isnt dit.related
        oldRelated = dit.related or null
        dit.setRelated model
        dit.onChange dit.instance, model, _.defaults(
          __related: oldRelated
        , options)
      return

    return

  removeRelated: (model, coll, options) ->
    return  unless @related
    if model is @related
      oldRelated = @related or null
      @setRelated null
      @onChange @instance, model, _.defaults(
        __related: oldRelated
      , options)
    return
)
Backbone.HasMany = Backbone.Relation.extend(
  collectionType: null
  options:
    reverseRelation:
      type: "HasOne"

    collectionType: Backbone.Collection
    collectionKey: true
    collectionOptions: {}

  initialize: (opts) ->
    @listenTo @instance, "relational:change:" + @key, @onChange
    
    # Handle a custom 'collectionType'
    @collectionType = @options.collectionType
    @collectionType = _.result(this, "collectionType")  if _.isFunction(@collectionType) and @collectionType isnt Backbone.Collection and (@collectionType:: not instanceof Backbone.Collection)
    @collectionType = Backbone.Relational.store.getObjectByName(@collectionType)  if _.isString(@collectionType)
    throw new Error("`collectionType` must inherit from Backbone.Collection")  if @collectionType isnt Backbone.Collection and (@collectionType:: not instanceof Backbone.Collection)
    related = @findRelated(opts)
    @setRelated related
    return

  
  ###
  Bind events and setup collectionKeys for a collection that is to be used as the backing store for a HasMany.
  If no 'collection' is supplied, a new collection will be created of the specified 'collectionType' option.
  @param {Backbone.Collection} [collection]
  @return {Backbone.Collection}
  ###
  _prepareCollection: (collection) ->
    @stopListening @related  if @related
    if not collection or (collection not instanceof Backbone.Collection)
      options = (if _.isFunction(@options.collectionOptions) then @options.collectionOptions(@instance) else @options.collectionOptions)
      collection = new @collectionType(null, options)
    collection.model = @relatedModel
    if @options.collectionKey
      key = (if @options.collectionKey is true then @options.reverseRelation.key else @options.collectionKey)
      if collection[key] and collection[key] isnt @instance
        console.warn "Relation=%o; collectionKey=%s already exists on collection=%o", this, key, @options.collectionKey  if Backbone.Relational.showWarnings and typeof console isnt "undefined"
      else collection[key] = @instance  if key
    @listenTo(collection, "relational:add", @handleAddition).listenTo(collection, "relational:remove", @handleRemoval).listenTo collection, "relational:reset", @handleReset
    collection

  
  ###
  Find related Models.
  @param {Object} [options]
  @return {Backbone.Collection}
  ###
  findRelated: (options) ->
    related = null
    options = _.defaults(
      parse: @options.parse
    , options)
    
    # Replace 'this.related' by 'this.keyContents' if it is a Backbone.Collection
    if @keyContents instanceof Backbone.Collection
      @_prepareCollection @keyContents
      related = @keyContents
    
    # Otherwise, 'this.keyContents' should be an array of related object ids.
    # Re-use the current 'this.related' if it is a Backbone.Collection; otherwise, create a new collection.
    else
      toAdd = []
      _.each @keyContents, ((attributes) ->
        model = null
        if attributes instanceof @relatedModel
          model = attributes
        else
          
          # If `merge` is true, update models here, instead of during update.
          model = @relatedModel.findOrCreate(attributes, _.extend(
            merge: true
          , options,
            create: @options.createModels
          ))
        model and toAdd.push(model)
        return
      ), this
      if @related instanceof Backbone.Collection
        related = @related
      else
        related = @_prepareCollection()
      
      # By now, both `merge` and `parse` will already have been executed for models if they were specified.
      # Disable them to prevent additional calls.
      related.set toAdd, _.defaults(
        merge: false
        parse: false
      , options)
    
    # Remove entries from `keyIds` that were already part of the relation (and are thus 'unchanged')
    @keyIds = _.difference(@keyIds, _.pluck(related.models, "id"))
    related

  
  ###
  Normalize and reduce `keyContents` to a list of `ids`, for easier comparison
  @param {String|Number|String[]|Number[]|Backbone.Collection} keyContents
  ###
  setKeyContents: (keyContents) ->
    @keyContents = (if keyContents instanceof Backbone.Collection then keyContents else null)
    @keyIds = []
    if not @keyContents and (keyContents or keyContents is 0) # since 0 can be a valid `id` as well
      # Handle cases the an API/user supplies just an Object/id instead of an Array
      @keyContents = (if _.isArray(keyContents) then keyContents else [keyContents])
      _.each @keyContents, ((item) ->
        itemId = Backbone.Relational.store.resolveIdForItem(@relatedModel, item)
        @keyIds.push itemId  if itemId or itemId is 0
        return
      ), this
    return

  
  ###
  Event handler for `change:<key>`.
  If the contents of the key are changed, notify old & new reverse relations and initialize the new relation.
  ###
  onChange: (model, attr, options) ->
    options = (if options then _.clone(options) else {})
    @setKeyContents attr
    @changed = false
    related = @findRelated(options)
    @setRelated related
    unless options.silent
      dit = this
      Backbone.Relational.eventQueue.add ->
        
        # The `changed` flag can be set in `handleAddition` or `handleRemoval`
        if dit.changed
          dit.instance.trigger "change:" + dit.key, dit.instance, dit.related, options, true
          dit.changed = false
        return

    return

  
  ###
  When a model is added to a 'HasMany', trigger 'add' on 'this.instance' and notify reverse relations.
  (should be 'HasOne', must set 'this.instance' as their related).
  ###
  handleAddition: (model, coll, options) ->
    
    #console.debug('handleAddition called; args=%o', arguments);
    options = (if options then _.clone(options) else {})
    @changed = true
    _.each @getReverseRelations(model), ((relation) ->
      relation.addRelated @instance, options
      return
    ), this
    
    # Only trigger 'add' once the newly added model is initialized (so, has its relations set up)
    dit = this
    not options.silent and Backbone.Relational.eventQueue.add(->
      dit.instance.trigger "add:" + dit.key, model, dit.related, options
      return
    )
    return

  
  ###
  When a model is removed from a 'HasMany', trigger 'remove' on 'this.instance' and notify reverse relations.
  (should be 'HasOne', which should be nullified)
  ###
  handleRemoval: (model, coll, options) ->
    
    #console.debug('handleRemoval called; args=%o', arguments);
    options = (if options then _.clone(options) else {})
    @changed = true
    _.each @getReverseRelations(model), ((relation) ->
      relation.removeRelated @instance, null, options
      return
    ), this
    dit = this
    not options.silent and Backbone.Relational.eventQueue.add(->
      dit.instance.trigger "remove:" + dit.key, model, dit.related, options
      return
    )
    return

  handleReset: (coll, options) ->
    dit = this
    options = (if options then _.clone(options) else {})
    not options.silent and Backbone.Relational.eventQueue.add(->
      dit.instance.trigger "reset:" + dit.key, dit.related, options
      return
    )
    return

  tryAddRelated: (model, coll, options) ->
    item = _.contains(@keyIds, model.id)
    if item
      @addRelated model, options
      @keyIds = _.without(@keyIds, model.id)
    return

  addRelated: (model, options) ->
    
    # Allow 'model' to set up its relations before proceeding.
    # (which can result in a call to 'addRelated' from a relation of 'model')
    dit = this
    model.queue ->
      if dit.related and not dit.related.get(model)
        dit.related.add model, _.defaults(
          parse: false
        , options)
      return

    return

  removeRelated: (model, coll, options) ->
    @related.remove model, options  if @related.get(model)
    return
)

###
A type of Backbone.Model that also maintains relations to other models and collections.
New events when compared to the original:
- 'add:<key>' (model, related collection, options)
- 'remove:<key>' (model, related collection, options)
- 'change:<key>' (model, related model or collection, options)
###
Backbone.RelationalModel = Backbone.Model.extend(
  relations: null # Relation descriptions on the prototype
  _relations: null # Relation instances
  _isInitialized: false
  _deferProcessing: false
  _queue: null
  _attributeChangeFired: false # Keeps track of `change` event firing under some conditions (like nested `set`s)
  subModelTypeAttribute: "type"
  subModelTypes: null
  constructor: (attributes, options) ->
    
    # Nasty hack, for cases like 'model.get( <HasMany key> ).add( item )'.
    # Defer 'processQueue', so that when 'Relation.createModels' is used we trigger 'HasMany'
    # collection events only after the model is really fully set up.
    # Example: event for "p.on( 'add:jobs' )" -> "p.get('jobs').add( { company: c.id, person: p.id } )".
    if options and options.collection
      dit = this
      collection = @collection = options.collection
      
      # Prevent `collection` from cascading down to nested models; they shouldn't go into this `if` clause.
      delete options.collection

      @_deferProcessing = true
      processQueue = (model) ->
        if model is dit
          dit._deferProcessing = false
          dit.processQueue()
          collection.off "relational:add", processQueue
        return

      collection.on "relational:add", processQueue
      
      # So we do process the queue eventually, regardless of whether this model actually gets added to 'options.collection'.
      _.defer ->
        processQueue dit
        return

    Backbone.Relational.store.processOrphanRelations()
    Backbone.Relational.store.listenTo this, "relational:unregister", Backbone.Relational.store.unregister
    @_queue = new Backbone.BlockingQueue()
    @_queue.block()
    Backbone.Relational.eventQueue.block()
    try
      Backbone.Model.apply this, arguments
    finally
      
      # Try to run the global queue holding external events
      Backbone.Relational.eventQueue.unblock()
    return

  
  ###
  Override 'trigger' to queue 'change' and 'change:*' events
  ###
  trigger: (eventName) ->
    if eventName.length > 5 and eventName.indexOf("change") is 0
      dit = this
      args = arguments
      unless Backbone.Relational.eventQueue.isLocked()
        
        # If we're not in a more complicated nested scenario, fire the change event right away
        Backbone.Model::trigger.apply dit, args
      else
        Backbone.Relational.eventQueue.add ->
          
          # Determine if the `change` event is still valid, now that all relations are populated
          changed = true
          if eventName is "change"
            
            # `hasChanged` may have gotten reset by nested calls to `set`.
            changed = dit.hasChanged() or dit._attributeChangeFired
            dit._attributeChangeFired = false
          else
            attr = eventName.slice(7)
            rel = dit.getRelation(attr)
            if rel
              
              # If `attr` is a relation, `change:attr` get triggered from `Relation.onChange`.
              # These take precedence over `change:attr` events triggered by `Model.set`.
              # The relation sets a fourth attribute to `true`. If this attribute is present,
              # continue triggering this event; otherwise, it's from `Model.set` and should be stopped.
              changed = (args[4] is true)
              
              # If this event was triggered by a relation, set the right value in `this.changed`
              # (a Collection or Model instead of raw data).
              if changed
                dit.changed[attr] = args[2]
              
              # Otherwise, this event is from `Model.set`. If the relation doesn't report a change,
              # remove attr from `dit.changed` so `hasChanged` doesn't take it into account.
              else delete dit.changed[attr]  unless rel.changed
            else dit._attributeChangeFired = true  if changed
          changed and Backbone.Model::trigger.apply(dit, args)
          return

    else if eventName is "destroy"
      Backbone.Model::trigger.apply this, arguments
      Backbone.Relational.store.unregister this
    else
      Backbone.Model::trigger.apply this, arguments
    this

  
  ###
  Initialize Relations present in this.relations; determine the type (HasOne/HasMany), then creates a new instance.
  Invoked in the first call so 'set' (which is made from the Backbone.Model constructor).
  ###
  initializeRelations: (options) ->
    @acquire() # Setting up relations often also involve calls to 'set', and we only want to enter this function once
    @_relations = {}
    _.each @relations or [], ((rel) ->
      Backbone.Relational.store.initializeRelation this, rel, options
      return
    ), this
    @_isInitialized = true
    @release()
    @processQueue()
    return

  
  ###
  When new values are set, notify this model's relations (also if options.silent is set).
  (called from `set`; Relation.setRelated locks this model before calling 'set' on it to prevent loops)
  @param {Object} [changedAttrs]
  @param {Object} [options]
  ###
  updateRelations: (changedAttrs, options) ->
    if @_isInitialized and not @isLocked()
      _.each @_relations, ((rel) ->
        if not changedAttrs or (rel.keySource of changedAttrs or rel.key of changedAttrs)
          
          # Fetch data in `rel.keySource` if data got set in there, or `rel.key` otherwise
          value = @attributes[rel.keySource] or @attributes[rel.key]
          attr = changedAttrs and (changedAttrs[rel.keySource] or changedAttrs[rel.key])
          
          # Update a relation if its value differs from this model's attributes, or it's been explicitly nullified.
          # Which can also happen before the originally intended related model has been found (`val` is null).
          @trigger "relational:change:" + rel.key, this, value, options or {}  if rel.related isnt value or (value is null and attr is null)
        
        # Explicitly clear 'keySource', to prevent a leaky abstraction if 'keySource' differs from 'key'.
        delete @attributes[rel.keySource]  if rel.keySource isnt rel.key
        return
      ), this
    return

  
  ###
  Either add to the queue (if we're not initialized yet), or execute right away.
  ###
  queue: (func) ->
    @_queue.add func
    return

  
  ###
  Process _queue
  ###
  processQueue: ->
    @_queue.unblock()  if @_isInitialized and not @_deferProcessing and @_queue.isBlocked()
    return

  
  ###
  Get a specific relation.
  @param {string} attr The relation key to look for.
  @return {Backbone.Relation} An instance of 'Backbone.Relation', if a relation was found for 'attr', or null.
  ###
  getRelation: (attr) ->
    debugger
    @_relations[attr]

  
  ###
  Get all of the created relations.
  @return {Backbone.Relation[]}
  ###
  getRelations: ->
    _.values @_relations

  
  ###
  Get a list of ids that will be fetched on a call to `fetchRelated`.
  @param {string|Backbone.Relation} attr The relation key to fetch models for.
  @param [refresh=false] Add ids for models that are already in the relation, refreshing them?
  @return {Array} An array of ids that need to be fetched.
  ###
  getIdsToFetch: (attr, refresh) ->
    rel = (if attr instanceof Backbone.Relation then attr else @getRelation(attr))
    ids = (if rel then (rel.keyIds and rel.keyIds.slice(0)) or ((if (rel.keyId or rel.keyId is 0) then [rel.keyId] else [])) else [])
    
    # On `refresh`, add the ids for current models in the relation to `idsToFetch`
    if refresh
      models = rel.related and (rel.related.models or [rel.related])
      _.each models, (model) ->
        ids.push model.id  if model.id or model.id is 0
        return

    ids

  
  ###
  Retrieve related objects.
  @param {string} attr The relation key to fetch models for.
  @param {Object} [options] Options for 'Backbone.Model.fetch' and 'Backbone.sync'.
  @param {Boolean} [refresh=false] Fetch existing models from the server as well (in order to update them).
  @return {jQuery.Deferred} A jQuery promise object
  ###
  fetchRelated: (attr, options, refresh) ->
    
    # Set default `options` for fetch
    options = _.extend(
      update: true
      remove: false
    , options)
    models = undefined
    setUrl = undefined
    requests = []
    rel = @getRelation(attr)
    idsToFetch = rel and @getIdsToFetch(rel, refresh)
    if idsToFetch and idsToFetch.length
      
      # Find (or create) a model for each one that is to be fetched
      created = []
      models = _.map(idsToFetch, (id) ->
        model = rel.relatedModel.findModel(id)
        unless model
          attrs = {}
          attrs[rel.relatedModel::idAttribute] = id
          model = rel.relatedModel.findOrCreate(attrs, options)
          created.push model
        model
      , this)
      
      # Try if the 'collection' can provide a url to fetch a set of models in one request.
      setUrl = rel.related.url(models)  if rel.related instanceof Backbone.Collection and _.isFunction(rel.related.url)
      
      # An assumption is that when 'Backbone.Collection.url' is a function, it can handle building of set urls.
      # To make sure it can, test if the url we got by supplying a list of models to fetch is different from
      # the one supplied for the default fetch action (without args to 'url').
      if setUrl and setUrl isnt rel.related.url()
        opts = _.defaults(
          error: ->
            args = arguments
            _.each created, (model) ->
              model.trigger "destroy", model, model.collection, options
              options.error and options.error.apply(model, args)
              return

            return

          url: setUrl
        , options)
        requests = [rel.related.fetch(opts)]
      else
        requests = _.map(models, (model) ->
          opts = _.defaults(
            error: ->
              if _.contains(created, model)
                model.trigger "destroy", model, model.collection, options
                options.error and options.error.apply(model, arguments)
              return
          , options)
          model.fetch opts
        , this)
    $.when.apply null, requests

  getAsync: (attr, options) ->
    dit = this
    @fetchRelated(attr, options).then ->
      Backbone.Model::get.call dit, attr


  set: (key, value, options) ->
    Backbone.Relational.eventQueue.block()
    
    # Duplicate backbone's behavior to allow separate key/value parameters, instead of a single 'attributes' object
    attributes = undefined
    result = undefined
    if _.isObject(key) or not key?
      attributes = key
      options = value
    else
      attributes = {}
      attributes[key] = value
    try
      id = @id
      newId = attributes and @idAttribute of attributes and attributes[@idAttribute]
      
      # Check if we're not setting a duplicate id before actually calling `set`.
      Backbone.Relational.store.checkId this, newId
      result = Backbone.Model::set.apply(this, arguments)
      
      # Ideal place to set up relations, if this is the first time we're here for this model
      if not @_isInitialized and not @isLocked()
        @constructor.initializeModelHierarchy()
        
        # Only register models that have an id. A model will be registered when/if it gets an id later on.
        Backbone.Relational.store.register this  if newId or newId is 0
        @initializeRelations options
      
      # The store should know about an `id` update asap
      else Backbone.Relational.store.update this  if newId and newId isnt id
      @updateRelations attributes, options  if attributes
    finally
      
      # Try to run the global queue holding external events
      Backbone.Relational.eventQueue.unblock()
    result

  clone: ->
    attributes = _.clone(@attributes)
    attributes[@idAttribute] = null  unless _.isUndefined(attributes[@idAttribute])
    _.each @getRelations(), (rel) ->
      delete attributes[rel.key]

      return

    new @constructor(attributes)

  
  ###
  Convert relations to JSON, omits them when required
  ###
  toJSON: (options) ->
    
    # If this Model has already been fully serialized in this branch once, return to avoid loops
    return @id  if @isLocked()
    @acquire()
    json = Backbone.Model::toJSON.call(this, options)
    json[@constructor._subModelTypeAttribute] = @constructor._subModelTypeValue  if @constructor._superModel and (@constructor._subModelTypeAttribute not of json)
    _.each @_relations, (rel) ->
      related = json[rel.key]
      includeInJSON = rel.options.includeInJSON
      value = null
      if includeInJSON is true
        value = related.toJSON(options)  if related and _.isFunction(related.toJSON)
      else if _.isString(includeInJSON)
        if related instanceof Backbone.Collection
          value = related.pluck(includeInJSON)
        else value = related.get(includeInJSON)  if related instanceof Backbone.Model
        
        # Add ids for 'unfound' models if includeInJSON is equal to (only) the relatedModel's `idAttribute`
        if includeInJSON is rel.relatedModel::idAttribute
          if rel instanceof Backbone.HasMany
            value = value.concat(rel.keyIds)
          else if rel instanceof Backbone.HasOne
            value = value or rel.keyId
            value = rel.keyContents or null  if not value and not _.isObject(rel.keyContents)
      else if _.isArray(includeInJSON)
        if related instanceof Backbone.Collection
          value = []
          related.each (model) ->
            curJson = {}
            _.each includeInJSON, (key) ->
              curJson[key] = model.get(key)
              return

            value.push curJson
            return

        else if related instanceof Backbone.Model
          value = {}
          _.each includeInJSON, (key) ->
            value[key] = related.get(key)
            return

      else
        delete json[rel.key]
      
      # In case of `wait: true`, Backbone will simply push whatever's passed into `save` into attributes.
      # We'll want to get this information into the JSON, even if it doesn't conform to our normal
      # expectations of what's contained in it (no model/collection for a relation, etc).
      value = related  if value is null and options and options.wait
      json[rel.keyDestination] = value  if includeInJSON
      delete json[rel.key]  if rel.keyDestination isnt rel.key
      return

    @release()
    json
,
  
  ###
  @param superModel
  @returns {Backbone.RelationalModel.constructor}
  ###
  setup: (superModel) ->
    
    # We don't want to share a relations array with a parent, as this will cause problems with reverse
    # relations. Since `relations` may also be a property or function, only use slice if we have an array.
    @::relations = (@::relations or []).slice(0)
    @_subModels = {}
    @_superModel = null
    
    # If this model has 'subModelTypes' itself, remember them in the store
    if @::hasOwnProperty("subModelTypes")
      Backbone.Relational.store.addSubModels @::subModelTypes, this
    
    # The 'subModelTypes' property should not be inherited, so reset it.
    else
      @::subModelTypes = null
    
    # Initialize all reverseRelations that belong to this new model.
    _.each @::relations or [], ((rel) ->
      rel.model = this  unless rel.model
      if rel.reverseRelation and rel.model is this
        preInitialize = true
        if _.isString(rel.relatedModel)
          
          ###
          The related model might not be defined for two reasons
          1. it is related to itself
          2. it never gets defined, e.g. a typo
          3. the model hasn't been defined yet, but will be later
          In neither of these cases do we need to pre-initialize reverse relations.
          However, for 3. (which is, to us, indistinguishable from 2.), we do need to attempt
          setting up this relation again later, in case the related model is defined later.
          ###
          relatedModel = Backbone.Relational.store.getObjectByName(rel.relatedModel)
          preInitialize = relatedModel and (relatedModel:: instanceof Backbone.RelationalModel)
        if preInitialize
          Backbone.Relational.store.initializeRelation null, rel
        else Backbone.Relational.store.addOrphanRelation rel  if _.isString(rel.relatedModel)
      return
    ), this
    this

  
  ###
  Create a 'Backbone.Model' instance based on 'attributes'.
  @param {Object} attributes
  @param {Object} [options]
  @return {Backbone.Model}
  ###
  build: (attributes, options) ->
    
    # 'build' is a possible entrypoint; it's possible no model hierarchy has been determined yet.
    @initializeModelHierarchy()
    
    # Determine what type of (sub)model should be built if applicable.
    model = @_findSubModelType(this, attributes) or this
    new model(attributes, options)

  
  ###
  Determines what type of (sub)model should be built if applicable.
  Looks up the proper subModelType in 'this._subModels', recursing into
  types until a match is found.  Returns the applicable 'Backbone.Model'
  or null if no match is found.
  @param {Backbone.Model} type
  @param {Object} attributes
  @return {Backbone.Model}
  ###
  _findSubModelType: (type, attributes) ->
    if type._subModels and type::subModelTypeAttribute of attributes
      subModelTypeAttribute = attributes[type::subModelTypeAttribute]
      subModelType = type._subModels[subModelTypeAttribute]
      if subModelType
        return subModelType
      else
        
        # Recurse into subModelTypes to find a match
        for subModelTypeAttribute of type._subModels
          subModelType = @_findSubModelType(type._subModels[subModelTypeAttribute], attributes)
          return subModelType  if subModelType
    null

  
  ###
  ###
  initializeModelHierarchy: ->
    
    # Inherit any relations that have been defined in the parent model.
    @inheritRelations()
    
    # If we came here through 'build' for a model that has 'subModelTypes' then try to initialize the ones that
    # haven't been resolved yet.
    if @::subModelTypes
      resolvedSubModels = _.keys(@_subModels)
      unresolvedSubModels = _.omit(@::subModelTypes, resolvedSubModels)
      _.each unresolvedSubModels, (subModelTypeName) ->
        subModelType = Backbone.Relational.store.getObjectByName(subModelTypeName)
        subModelType and subModelType.initializeModelHierarchy()
        return

    return

  inheritRelations: ->
    
    # Bail out if we've been here before.
    return  if not _.isUndefined(@_superModel) and not _.isNull(@_superModel)
    
    # Try to initialize the _superModel.
    Backbone.Relational.store.setupSuperModel this
    
    # If a superModel has been found, copy relations from the _superModel if they haven't been inherited automatically
    # (due to a redefinition of 'relations').
    if @_superModel
      
      # The _superModel needs a chance to initialize its own inherited relations before we attempt to inherit relations
      # from the _superModel. You don't want to call 'initializeModelHierarchy' because that could cause sub-models of
      # this class to inherit their relations before this class has had chance to inherit it's relations.
      @_superModel.inheritRelations()
      if @_superModel::relations
        
        # Find relations that exist on the '_superModel', but not yet on this model.
        inheritedRelations = _.filter(@_superModel::relations or [], (superRel) ->
          not _.any(@::relations or [], (rel) ->
            superRel.relatedModel is rel.relatedModel and superRel.key is rel.key
          , this)
        , this)
        @::relations = inheritedRelations.concat(@::relations)
    
    # Otherwise, make sure we don't get here again for this type by making '_superModel' false so we fail the
    # isUndefined/isNull check next time.
    else
      @_superModel = false
    return

  
  ###
  Find an instance of `this` type in 'Backbone.Relational.store'.
  A new model is created if no matching model is found, `attributes` is an object, and `options.create` is true.
  - If `attributes` is a string or a number, `findOrCreate` will query the `store` and return a model if found.
  - If `attributes` is an object and is found in the store, the model will be updated with `attributes` unless `options.update` is `false`.
  @param {Object|String|Number} attributes Either a model's id, or the attributes used to create or update a model.
  @param {Object} [options]
  @param {Boolean} [options.create=true]
  @param {Boolean} [options.merge=true]
  @param {Boolean} [options.parse=false]
  @return {Backbone.RelationalModel}
  ###
  findOrCreate: (attributes, options) ->
    options or (options = {})
    parsedAttributes = (if (_.isObject(attributes) and options.parse and @::parse) then @::parse(_.clone(attributes)) else attributes)
    
    # If specified, use a custom `find` function to match up existing models to the given attributes.
    # Otherwise, try to find an instance of 'this' model type in the store
    model = @findModel(parsedAttributes)
    
    # If we found an instance, update it with the data in 'item' (unless 'options.merge' is false).
    # If not, create an instance (unless 'options.create' is false).
    if _.isObject(attributes)
      if model and options.merge isnt false
        
        # Make sure `options.collection` and `options.url` doesn't cascade to nested models
        delete options.collection

        delete options.url

        model.set parsedAttributes, options
      else if not model and options.create isnt false
        model = @build(parsedAttributes, _.defaults(
          parse: false
        , options))
    model

  
  ###
  Find an instance of `this` type in 'Backbone.Relational.store'.
  - If `attributes` is a string or a number, `find` will query the `store` and return a model if found.
  - If `attributes` is an object and is found in the store, the model will be updated with `attributes` unless `options.update` is `false`.
  @param {Object|String|Number} attributes Either a model's id, or the attributes used to create or update a model.
  @param {Object} [options]
  @param {Boolean} [options.merge=true]
  @param {Boolean} [options.parse=false]
  @return {Backbone.RelationalModel}
  ###
  find: (attributes, options) ->
    options or (options = {})
    options.create = false
    @findOrCreate attributes, options

  
  ###
  A hook to override the matching when updating (or creating) a model.
  The default implementation is to look up the model by id in the store.
  @param {Object} attributes
  @returns {Backbone.RelationalModel}
  ###
  findModel: (attributes) ->
    Backbone.Relational.store.find this, attributes
)
_.extend Backbone.RelationalModel::, Backbone.Semaphore

###
Override Backbone.Collection._prepareModel, so objects will be built using the correct type
if the collection.model has subModels.
Attempts to find a model for `attrs` in Backbone.store through `findOrCreate`
(which sets the new properties on it if found), or instantiates a new model.
###
Backbone.Collection::__prepareModel = Backbone.Collection::_prepareModel
Backbone.Collection::_prepareModel = (attrs, options) ->
  model = undefined
  if attrs instanceof Backbone.Model
    attrs.collection = this  unless attrs.collection
    model = attrs
  else
    options = (if options then _.clone(options) else {})
    options.collection = this
    if typeof @model.findOrCreate isnt "undefined"
      model = @model.findOrCreate(attrs, options)
    else
      model = new @model(attrs, options)
    if model and model.validationError
      @trigger "invalid", this, attrs, options
      model = false
  model


###
Override Backbone.Collection.set, so we'll create objects from attributes where required,
and update the existing models. Also, trigger 'relational:add'.
###
set = Backbone.Collection::__set = Backbone.Collection::set
Backbone.Collection::set = (models, options) ->
  
  # Short-circuit if this Collection doesn't hold RelationalModels
  return set.apply(this, arguments)  unless @model:: instanceof Backbone.RelationalModel
  models = @parse(models, options)  if options and options.parse
  singular = not _.isArray(models)
  newModels = []
  toAdd = []
  models = (if singular then ((if models then [models] else [])) else _.clone(models))
  
  #console.debug( 'calling add on coll=%o; model=%o, options=%o', this, models, options );
  _.each models, ((model) ->
    model = Backbone.Collection::_prepareModel.call(this, model, options)  unless model instanceof Backbone.Model
    if model
      toAdd.push model
      unless @get(model) or @get(model.cid)
        newModels.push model
      
      # If we arrive in `add` while performing a `set` (after a create, so the model gains an `id`),
      # we may get here before `_onModelEvent` has had the chance to update `_byId`.
      else @_byId[model.id] = model  if model.id?
    return
  ), this
  
  # Add 'models' in a single batch, so the original add will only be called once (and thus 'sort', etc).
  # If `parse` was specified, the collection and contained models have been parsed now.
  toAdd = (if singular then ((if toAdd.length then toAdd[0] else null)) else toAdd)
  result = set.call(this, toAdd, _.defaults(
    parse: false
  , options))
  _.each newModels, ((model) ->
    
    # Fire a `relational:add` event for any model in `newModels` that has actually been added to the collection.
    @trigger "relational:add", model, this, options  if @get(model) or @get(model.cid)
    return
  ), this
  result


###
Override 'Backbone.Collection.remove' to trigger 'relational:remove'.
###
remove = Backbone.Collection::__remove = Backbone.Collection::remove
Backbone.Collection::remove = (models, options) ->
  
  # Short-circuit if this Collection doesn't hold RelationalModels
  return remove.apply(this, arguments)  unless @model:: instanceof Backbone.RelationalModel
  singular = not _.isArray(models)
  toRemove = []
  models = (if singular then ((if models then [models] else [])) else _.clone(models))
  options or (options = {})
  
  #console.debug('calling remove on coll=%o; models=%o, options=%o', this, models, options );
  _.each models, ((model) ->
    model = @get(model) or (model and @get(model.cid))
    model and toRemove.push(model)
    return
  ), this
  result = remove.call(this, (if singular then ((if toRemove.length then toRemove[0] else null)) else toRemove), options)
  _.each toRemove, ((model) ->
    @trigger "relational:remove", model, this, options
    return
  ), this
  result


###
Override 'Backbone.Collection.reset' to trigger 'relational:reset'.
###
reset = Backbone.Collection::__reset = Backbone.Collection::reset
Backbone.Collection::reset = (models, options) ->
  options = _.extend(
    merge: true
  , options)
  result = reset.call(this, models, options)
  @trigger "relational:reset", this, options  if @model:: instanceof Backbone.RelationalModel
  result


###
Override 'Backbone.Collection.sort' to trigger 'relational:reset'.
###
sort = Backbone.Collection::__sort = Backbone.Collection::sort
Backbone.Collection::sort = (options) ->
  result = sort.call(this, options)
  @trigger "relational:reset", this, options  if @model:: instanceof Backbone.RelationalModel
  result


###
Override 'Backbone.Collection.trigger' so 'add', 'remove' and 'reset' events are queued until relations
are ready.
###
trigger = Backbone.Collection::__trigger = Backbone.Collection::trigger
Backbone.Collection::trigger = (eventName) ->
  
  # Short-circuit if this Collection doesn't hold RelationalModels
  return trigger.apply(this, arguments)  unless @model:: instanceof Backbone.RelationalModel
  if eventName is "add" or eventName is "remove" or eventName is "reset" or eventName is "sort"
    dit = this
    args = arguments
    if _.isObject(args[3])
      args = _.toArray(args)
      
      # the fourth argument is the option object.
      # we need to clone it, as it could be modified while we wait on the eventQueue to be unblocked
      args[3] = _.clone(args[3])
    Backbone.Relational.eventQueue.add ->
      trigger.apply dit, args
      return

  else
    trigger.apply this, arguments
  this


# Override .extend() to automatically call .setup()
Backbone.RelationalModel.extend = (protoProps, classProps) ->
  child = Backbone.Model.extend.apply(this, arguments)
  child.setup this
  child

