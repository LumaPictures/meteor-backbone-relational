#     Backbone.js 1.1.2

#     (c) 2010-2014 Jeremy Ashkenas, DocumentCloud and Investigative Reporters & Editors
#     Backbone may be freely distributed under the MIT license.
#     For all details and documentation:
#     http://backbonejs.org

# Initial Setup
# -------------
@Backbone = Backbone = {}


# Create local references to array methods we'll want to use later.
array = []
slice = array.slice

# Current version of the library. Keep in sync with `package.json`.
Backbone.VERSION = "1.1.2"

# For Backbone's purposes, jQuery, Zepto, Ender, or My Library (kidding) owns
# the `$` variable.
Backbone.$ = $ if Meteor.isClient


# Turn on `emulateHTTP` to support legacy HTTP servers. Setting this option
# will fake `"PATCH"`, `"PUT"` and `"DELETE"` requests via the `_method` parameter and
# set a `X-Http-Method-Override` header.
Backbone.emulateHTTP = false

# Turn on `emulateJSON` to support legacy servers that can't deal with direct
# `application/json` requests ... will encode the body as
# `application/x-www-form-urlencoded` instead and will send the model in a
# form param named `model`.
Backbone.emulateJSON = false

# Backbone.Events
# ---------------

# A module that can be mixed in to *any object* in order to provide it with
# custom events. You may bind with `on` or remove with `off` callback
# functions to an event; `trigger`-ing an event fires all callbacks in
# succession.
#
#     var object = {};
#     _.extend(object, Backbone.Events);
#     object.on('expand', function(){ alert('expanded'); });
#     object.trigger('expand');
#
Events = Backbone.Events =
  
  # Bind an event to a `callback` function. Passing `"all"` will bind
  # the callback to all events fired.
  on: (name, callback, context) ->
    return this  if not eventsApi(this, "on", name, [
      callback
      context
    ]) or not callback
    @_events or (@_events = {})
    events = @_events[name] or (@_events[name] = [])
    events.push
      callback: callback
      context: context
      ctx: context or this

    this

  
  # Bind an event to only be triggered a single time. After the first time
  # the callback is invoked, it will be removed.
  once: (name, callback, context) ->
    return this  if not eventsApi(this, "once", name, [
      callback
      context
    ]) or not callback
    self = this
    once = _.once(->
      self.off name, once
      callback.apply this, arguments
      return
    )
    once._callback = callback
    @on name, once, context

  
  # Remove one or many callbacks. If `context` is null, removes all
  # callbacks with that function. If `callback` is null, removes all
  # callbacks for the event. If `name` is null, removes all bound
  # callbacks for all events.
  off: (name, callback, context) ->
    return this  if not @_events or not eventsApi(this, "off", name, [
      callback
      context
    ])
    
    # Remove all callbacks for all events.
    if not name and not callback and not context
      @_events = undefined
      return this
    names = (if name then [name] else _.keys(@_events))
    i = 0
    length = names.length

    while i < length
      name = names[i]
      
      # Bail out if there are no events stored.
      events = @_events[name]
      continue  unless events
      
      # Remove all callbacks for this event.
      if not callback and not context
        delete @_events[name]

        continue
      
      # Find any remaining events.
      remaining = []
      j = 0
      k = events.length

      while j < k
        event = events[j]
        remaining.push event  if callback and callback isnt event.callback and callback isnt event.callback._callback or context and context isnt event.context
        j++
      
      # Replace events if there are any remaining.  Otherwise, clean up.
      if remaining.length
        @_events[name] = remaining
      else
        delete @_events[name]
      i++
    this

  
  # Trigger one or many events, firing all bound callbacks. Callbacks are
  # passed the same arguments as `trigger` is, apart from the event name
  # (unless you're listening on `"all"`, which will cause your callback to
  # receive the true name of the event as the first argument).
  trigger: (name) ->
    return this  unless @_events
    args = slice.call(arguments, 1)
    return this  unless eventsApi(this, "trigger", name, args)
    events = @_events[name]
    allEvents = @_events.all
    triggerEvents events, args  if events
    triggerEvents allEvents, arguments  if allEvents
    this

  
  # Tell this object to stop listening to either specific events ... or
  # to every object it's currently listening to.
  stopListening: (obj, name, callback) ->
    listeningTo = @_listeningTo
    return this  unless listeningTo
    remove = not name and not callback
    callback = this  if not callback and typeof name is "object"
    (listeningTo = {})[obj._listenId] = obj  if obj
    for id of listeningTo
      obj = listeningTo[id]
      obj.off name, callback, this
      delete @_listeningTo[id]  if remove or _.isEmpty(obj._events)
    this


# Regular expression used to split event strings.
eventSplitter = /\s+/

# Implement fancy features of the Events API such as multiple event
# names `"change blur"` and jQuery-style event maps `{change: action}`
# in terms of the existing API.
eventsApi = (obj, action, name, rest) ->
  return true  unless name
  
  # Handle event maps.
  if typeof name is "object"
    for key of name
      obj[action].apply obj, [
        key
        name[key]
      ].concat(rest)
    return false
  
  # Handle space separated event names.
  if eventSplitter.test(name)
    names = name.split(eventSplitter)
    i = 0
    length = names.length

    while i < length
      obj[action].apply obj, [names[i]].concat(rest)
      i++
    return false
  true


# A difficult-to-believe, but optimized internal dispatch function for
# triggering events. Tries to keep the usual cases speedy (most internal
# Backbone events have 3 arguments).
triggerEvents = (events, args) ->
  ev = undefined
  i = -1
  l = events.length
  a1 = args[0]
  a2 = args[1]
  a3 = args[2]
  switch args.length
    when 0
      (ev = events[i]).callback.call ev.ctx  while ++i < l
      return
    when 1
      (ev = events[i]).callback.call ev.ctx, a1  while ++i < l
      return
    when 2
      (ev = events[i]).callback.call ev.ctx, a1, a2  while ++i < l
      return
    when 3
      (ev = events[i]).callback.call ev.ctx, a1, a2, a3  while ++i < l
      return
    else
      (ev = events[i]).callback.apply ev.ctx, args  while ++i < l
      return

listenMethods =
  listenTo: "on"
  listenToOnce: "once"


# Inversion-of-control versions of `on` and `once`. Tell *this* object to
# listen to an event in another object ... keeping track of what it's
# listening to.
_.each listenMethods, (implementation, method) ->
  Events[method] = (obj, name, callback) ->
    listeningTo = @_listeningTo or (@_listeningTo = {})
    id = obj._listenId or (obj._listenId = _.uniqueId("l"))
    listeningTo[id] = obj
    callback = this  if not callback and typeof name is "object"
    obj[implementation] name, callback, this
    this

  return


# Aliases for backwards compatibility.
Events.bind = Events.on
Events.unbind = Events.off

# Allow the `Backbone` object to serve as a global event bus, for folks who
# want global "pubsub" in a convenient place.
_.extend Backbone, Events

# Backbone.Model
# --------------

# Backbone **Models** are the basic data object in the framework --
# frequently representing a row in a table in a database on your server.
# A discrete chunk of data and a bunch of useful, related methods for
# performing computations and transformations on that data.

# Create a new model with the specified attributes. A client id (`cid`)
# is automatically generated and assigned for you.
Model = Backbone.Model = (attributes, options) ->
  attrs = attributes or {}
  options or (options = {})
  @cid = _.uniqueId("c")
  @attributes = {}
  @collection = options.collection  if options.collection
  attrs = @parse(attrs, options) or {}  if options.parse
  attrs = _.defaults({}, attrs, _.result(this, "defaults"))
  @set attrs, options
  @changed = {}
  @initialize.apply this, arguments
  return


# Attach all inheritable methods to the Model prototype.
_.extend Model::, Events,
  
  # A hash of attributes whose current and previous value differ.
  changed: null
  
  # The value returned during the last failed validation.
  validationError: null
  
  # The default name for the JSON `id` attribute is `"id"`. MongoDB and
  # CouchDB users may want to set this to `"_id"`.
  idAttribute: "id"
  
  # Initialize is an empty function by default. Override it with your own
  # initialization logic.
  initialize: ->

  
  # Return a copy of the model's `attributes` object.
  toJSON: (options) ->
    _.clone @attributes

  
  # Proxy `Backbone.sync` by default -- but override this if you need
  # custom syncing semantics for *this* particular model.
  sync: ->
    Backbone.sync.apply this, arguments

  
  # Get the value of an attribute.
  get: (attr) ->
    @attributes[attr]

  
  # Get the HTML-escaped value of an attribute.
  escape: (attr) ->
    _.escape @get(attr)

  
  # Returns `true` if the attribute contains a value that is not null
  # or undefined.
  has: (attr) ->
    @get(attr)?

  
  # Set a hash of model attributes on the object, firing `"change"`. This is
  # the core primitive operation of a model, updating the data and notifying
  # anyone who needs to know about the change in state. The heart of the beast.
  set: (key, val, options) ->
    attr = undefined
    attrs = undefined
    unset = undefined
    changes = undefined
    silent = undefined
    changing = undefined
    prev = undefined
    current = undefined
    return this  unless key?
    
    # Handle both `"key", value` and `{key: value}` -style arguments.
    if typeof key is "object"
      attrs = key
      options = val
    else
      (attrs = {})[key] = val
    options or (options = {})
    
    # Run validation.
    return false  unless @_validate(attrs, options)
    
    # Extract attributes and options.
    unset = options.unset
    silent = options.silent
    changes = []
    changing = @_changing
    @_changing = true
    unless changing
      @_previousAttributes = _.clone(@attributes)
      @changed = {}
    current = @attributes
    prev = @_previousAttributes

    
    # Check for changes of `id`.
    @id = attrs[@idAttribute]  if @idAttribute of attrs
    
    # For each `set` attribute, update or delete the current value.
    for attr of attrs
      val = attrs[attr]
      changes.push attr  unless _.isEqual(current[attr], val)
      unless _.isEqual(prev[attr], val)
        @changed[attr] = val
      else
        delete @changed[attr]
      if unset then delete current[attr]
      else current[attr] = val
    
    # Trigger all relevant attribute changes.
    unless silent
      @_pending = options  if changes.length
      i = 0
      length = changes.length

      while i < length
        @trigger "change:" + changes[i], this, current[changes[i]], options
        i++
    
    # You might be wondering why there's a `while` loop here. Changes can
    # be recursively nested within `"change"` events.
    return this  if changing
    unless silent
      while @_pending
        options = @_pending
        @_pending = false
        @trigger "change", this, options
    @_pending = false
    @_changing = false
    this

  
  # Remove an attribute from the model, firing `"change"`. `unset` is a noop
  # if the attribute doesn't exist.
  unset: (attr, options) ->
    @set attr, undefined, _.extend({}, options,
      unset: true
    )

  
  # Clear all attributes on the model, firing `"change"`.
  clear: (options) ->
    attrs = {}
    for key of @attributes
      continue
    @set attrs, _.extend({}, options,
      unset: true
    )

  
  # Determine if the model has changed since the last `"change"` event.
  # If you specify an attribute name, determine if that attribute has changed.
  hasChanged: (attr) ->
    return not _.isEmpty(@changed)  unless attr?
    _.has @changed, attr

  
  # Return an object containing all the attributes that have changed, or
  # false if there are no changed attributes. Useful for determining what
  # parts of a view need to be updated and/or what attributes need to be
  # persisted to the server. Unset attributes will be set to undefined.
  # You can also pass an attributes object to diff against the model,
  # determining if there *would be* a change.
  changedAttributes: (diff) ->
    return (if @hasChanged() then _.clone(@changed) else false)  unless diff
    val = undefined
    changed = false
    old = (if @_changing then @_previousAttributes else @attributes)
    for attr of diff
      continue  if _.isEqual(old[attr], (val = diff[attr]))
      (changed or (changed = {}))[attr] = val
    changed

  
  # Get the previous value of an attribute, recorded at the time the last
  # `"change"` event was fired.
  previous: (attr) ->
    return null  if not attr? or not @_previousAttributes
    @_previousAttributes[attr]

  
  # Get all of the attributes of the model at the time of the previous
  # `"change"` event.
  previousAttributes: ->
    _.clone @_previousAttributes

  
  # Fetch the model from the server. If the server's representation of the
  # model differs from its current attributes, they will be overridden,
  # triggering a `"change"` event.
  fetch: (options) ->
    options = (if options then _.clone(options) else {})
    options.parse = true  if options.parse is undefined
    model = this
    success = options.success
    options.success = (resp) ->
      return false  unless model.set(model.parse(resp, options), options)
      success model, resp, options  if success
      model.trigger "sync", model, resp, options
      return

    wrapError this, options
    @sync "read", this, options

  
  # Set a hash of model attributes, and sync the model to the server.
  # If the server returns an attributes hash that differs, the model's
  # state will be `set` again.
  save: (key, val, options) ->
    attrs = undefined
    method = undefined
    xhr = undefined
    attributes = @attributes
    
    # Handle both `"key", value` and `{key: value}` -style arguments.
    if not key? or typeof key is "object"
      attrs = key
      options = val
    else
      (attrs = {})[key] = val
    options = _.extend(
      validate: true
    , options)
    
    # If we're not waiting and attributes exist, save acts as
    # `set(attr).save(null, opts)` with validation. Otherwise, check if
    # the model will be valid when the attributes, if any, are set.
    if attrs and not options.wait
      return false  unless @set(attrs, options)
    else
      return false  unless @_validate(attrs, options)
    
    # Set temporary attributes if `{wait: true}`.
    @attributes = _.extend({}, attributes, attrs)  if attrs and options.wait
    
    # After a successful server-side save, the client is (optionally)
    # updated with the server-side state.
    options.parse = true  if options.parse is undefined
    model = this
    success = options.success
    options.success = (resp) ->
      
      # Ensure attributes are restored during synchronous saves.
      model.attributes = attributes
      serverAttrs = model.parse(resp, options)
      serverAttrs = _.extend(attrs or {}, serverAttrs)  if options.wait
      return false  if _.isObject(serverAttrs) and not model.set(serverAttrs, options)
      success model, resp, options  if success
      model.trigger "sync", model, resp, options
      return

    wrapError this, options
    method = (if @isNew() then "create" else ((if options.patch then "patch" else "update")))
    options.attrs = attrs  if method is "patch"
    xhr = @sync(method, this, options)
    
    # Restore attributes.
    @attributes = attributes  if attrs and options.wait
    xhr

  
  # Destroy this model on the server if it was already persisted.
  # Optimistically removes the model from its collection, if it has one.
  # If `wait: true` is passed, waits for the server to respond before removal.
  destroy: (options) ->
    options = (if options then _.clone(options) else {})
    model = this
    success = options.success
    destroy = ->
      model.trigger "destroy", model, model.collection, options
      return

    options.success = (resp) ->
      destroy()  if options.wait or model.isNew()
      success model, resp, options  if success
      model.trigger "sync", model, resp, options  unless model.isNew()
      return

    if @isNew()
      options.success()
      return false
    wrapError this, options
    xhr = @sync("delete", this, options)
    destroy()  unless options.wait
    xhr

  
  # Default URL for the model's representation on the server -- if you're
  # using Backbone's restful methods, override this to change the endpoint
  # that will be called.
  url: ->
    base = _.result(this, "urlRoot") or _.result(@collection, "url") or urlError()
    return base  if @isNew()
    base.replace(/([^\/])$/, "$1/") + encodeURIComponent(@id)

  
  # **parse** converts a response into the hash of attributes to be `set` on
  # the model. The default implementation is just to pass the response along.
  parse: (resp, options) ->
    resp

  
  # Create a new model with identical attributes to this one.
  clone: ->
    new @constructor(@attributes)

  
  # A model is new if it has never been saved to the server, and lacks an id.
  isNew: ->
    not @has(@idAttribute)

  
  # Check if the model is currently in a valid state.
  isValid: (options) ->
    @_validate {}, _.extend(options or {},
      validate: true
    )

  
  # Run validation against the next complete set of model attributes,
  # returning `true` if all is well. Otherwise, fire an `"invalid"` event.
  _validate: (attrs, options) ->
    return true  if not options.validate or not @validate
    attrs = _.extend({}, @attributes, attrs)
    error = @validationError = @validate(attrs, options) or null
    return true  unless error
    @trigger "invalid", this, error, _.extend(options,
      validationError: error
    )
    false


# Underscore methods that we want to implement on the Model.
modelMethods = [
  "keys"
  "values"
  "pairs"
  "invert"
  "pick"
  "omit"
  "chain"
]

# Mix in each Underscore method as a proxy to `Model#attributes`.
_.each modelMethods, (method) ->
  return  unless _[method]
  Model::[method] = ->
    args = slice.call(arguments)
    args.unshift @attributes
    _[method].apply _, args

  return


# Backbone.Collection
# -------------------

# If models tend to represent a single row of data, a Backbone Collection is
# more analogous to a table full of data ... or a small slice or page of that
# table, or a collection of rows that belong together for a particular reason
# -- all of the messages in this particular folder, all of the documents
# belonging to this particular author, and so on. Collections maintain
# indexes of their models, both in order, and for lookup by `id`.

# Create a new **Collection**, perhaps to contain a specific type of `model`.
# If a `comparator` is specified, the Collection will maintain
# its models in sort order, as they're added and removed.
Collection = Backbone.Collection = (models, options) ->
  options or (options = {})
  @model = options.model  if options.model
  @comparator = options.comparator  if options.comparator isnt undefined
  @_reset()
  @initialize.apply this, arguments
  if models
    @reset models, _.extend(
      silent: true
    , options)
  return


# Default options for `Collection#set`.
setOptions =
  add: true
  remove: true
  merge: true

addOptions =
  add: true
  remove: false


# Define the Collection's inheritable methods.
_.extend Collection::, Events,
  
  # The default model for a collection is just a **Backbone.Model**.
  # This should be overridden in most cases.
  model: Model
  
  # Initialize is an empty function by default. Override it with your own
  # initialization logic.
  initialize: ->

  
  # The JSON representation of a Collection is an array of the
  # models' attributes.
  toJSON: (options) ->
    @map (model) ->
      model.toJSON options


  
  # Proxy `Backbone.sync` by default.
  sync: ->
    Backbone.sync.apply this, arguments

  
  # Add a model, or list of models to the set.
  add: (models, options) ->
    @set models, _.extend(
      merge: false
    , options, addOptions)

  
  # Remove a model, or a list of models from the set.
  remove: (models, options) ->
    singular = not _.isArray(models)
    models = (if singular then [models] else _.clone(models))
    options or (options = {})
    i = 0
    length = models.length

    while i < length
      model = models[i] = @get(models[i])
      continue  unless model
      delete @_byId[model.id]

      delete @_byId[model.cid]

      index = @indexOf(model)
      @models.splice index, 1
      @length--
      unless options.silent
        options.index = index
        model.trigger "remove", model, this, options
      @_removeReference model, options
      i++
    (if singular then models[0] else models)

  
  # Update a collection by `set`-ing a new list of models, adding new ones,
  # removing models that are no longer present, and merging models that
  # already exist in the collection, as necessary. Similar to **Model#set**,
  # the core operation for updating the data contained by the collection.
  set: (models, options) ->
    options = _.defaults({}, options, setOptions)
    models = @parse(models, options)  if options.parse
    singular = not _.isArray(models)
    models = (if singular then ((if models then [models] else [])) else models.slice())
    id = undefined
    model = undefined
    attrs = undefined
    existing = undefined
    sort = undefined
    at = options.at
    sortable = @comparator and (not (at?)) and options.sort isnt false
    sortAttr = (if _.isString(@comparator) then @comparator else null)
    toAdd = []
    toRemove = []
    modelMap = {}
    add = options.add
    merge = options.merge
    remove = options.remove
    order = (if not sortable and add and remove then [] else false)
    
    # Turn bare objects into model references, and prevent invalid models
    # from being added.
    i = 0
    length = models.length

    while i < length
      attrs = models[i] or {}
      if @_isModel(attrs)
        id = model = attrs
      else
        id = attrs[@model::idAttribute or "id"]
      
      # If a duplicate is found, prevent it from being added and
      # optionally merge it into the existing model.
      if existing = @get(id)
        modelMap[existing.cid] = true  if remove
        if merge
          attrs = (if attrs is model then model.attributes else attrs)
          attrs = existing.parse(attrs, options)  if options.parse
          existing.set attrs, options
          sort = true  if sortable and not sort and existing.hasChanged(sortAttr)
        models[i] = existing
      
      # If this is a new, valid model, push it to the `toAdd` list.
      else if add
        model = models[i] = @_prepareModel(attrs, options)
        continue  unless model
        toAdd.push model
        @_addReference model, options
      
      # Do not add multiple models with the same `id`.
      model = existing or model
      continue  unless model
      order.push model  if order and (model.isNew() or not modelMap[model.id])
      modelMap[model.id] = true
      i++
    
    # Remove nonexistent models if appropriate.
    if remove
      i = 0
      length = @length

      while i < length
        toRemove.push model  unless modelMap[(model = @models[i]).cid]
        i++
      @remove toRemove, options  if toRemove.length
    
    # See if sorting is needed, update `length` and splice in new models.
    if toAdd.length or (order and order.length)
      sort = true  if sortable
      @length += toAdd.length
      if at?
        i = 0
        length = toAdd.length

        while i < length
          @models.splice at + i, 0, toAdd[i]
          i++
      else
        @models.length = 0  if order
        orderedModels = order or toAdd
        i = 0
        length = orderedModels.length

        while i < length
          @models.push orderedModels[i]
          i++
    
    # Silently sort the collection if appropriate.
    @sort silent: true  if sort
    
    # Unless silenced, it's time to fire all appropriate add/sort events.
    unless options.silent
      i = 0
      length = toAdd.length

      while i < length
        (model = toAdd[i]).trigger "add", model, this, options
        i++
      @trigger "sort", this, options  if sort or (order and order.length)
    
    # Return the added (or merged) model (or models).
    (if singular then models[0] else models)

  
  # When you have more items than you want to add or remove individually,
  # you can reset the entire set with a new list of models, without firing
  # any granular `add` or `remove` events. Fires `reset` when finished.
  # Useful for bulk operations and optimizations.
  reset: (models, options) ->
    options or (options = {})
    i = 0
    length = @models.length

    while i < length
      @_removeReference @models[i], options
      i++
    options.previousModels = @models
    @_reset()
    models = @add(models, _.extend(
      silent: true
    , options))
    @trigger "reset", this, options  unless options.silent
    models

  
  # Add a model to the end of the collection.
  push: (model, options) ->
    @add model, _.extend(
      at: @length
    , options)

  
  # Remove a model from the end of the collection.
  pop: (options) ->
    model = @at(@length - 1)
    @remove model, options
    model

  
  # Add a model to the beginning of the collection.
  unshift: (model, options) ->
    @add model, _.extend(
      at: 0
    , options)

  
  # Remove a model from the beginning of the collection.
  shift: (options) ->
    model = @at(0)
    @remove model, options
    model

  
  # Slice out a sub-array of models from the collection.
  slice: ->
    slice.apply @models, arguments

  
  # Get a model from the set by id.
  get: (obj) ->
    return undefined  unless obj?
    @_byId[obj] or @_byId[obj.id] or @_byId[obj.cid]

  
  # Get the model at the given index.
  at: (index) ->
    @models[index]

  
  # Return models with matching attributes. Useful for simple cases of
  # `filter`.
  where: (attrs, first) ->
    return (if first then undefined else [])  if _.isEmpty(attrs)
    this[(if first then "find" else "filter")] (model) ->
      for key of attrs
        return false  if attrs[key] isnt model.get(key)
      true


  
  # Return the first model with matching attributes. Useful for simple cases
  # of `find`.
  findWhere: (attrs) ->
    @where attrs, true

  
  # Force the collection to re-sort itself. You don't need to call this under
  # normal circumstances, as the set will maintain sort order as each item
  # is added.
  sort: (options) ->
    throw new Error("Cannot sort a set without a comparator")  unless @comparator
    options or (options = {})
    
    # Run sort based on type of `comparator`.
    if _.isString(@comparator) or @comparator.length is 1
      @models = @sortBy(@comparator, this)
    else
      @models.sort _.bind(@comparator, this)
    @trigger "sort", this, options  unless options.silent
    this

  
  # Pluck an attribute from each model in the collection.
  pluck: (attr) ->
    _.invoke @models, "get", attr

  
  # Fetch the default set of models for this collection, resetting the
  # collection when they arrive. If `reset: true` is passed, the response
  # data will be passed through the `reset` method instead of `set`.
  fetch: (options) ->
    options = (if options then _.clone(options) else {})
    options.parse = true  if options.parse is undefined
    success = options.success
    collection = this
    options.success = (resp) ->
      method = (if options.reset then "reset" else "set")
      collection[method] resp, options
      success collection, resp, options  if success
      collection.trigger "sync", collection, resp, options
      return

    wrapError this, options
    @sync "read", this, options

  
  # Create a new instance of a model in this collection. Add the model to the
  # collection immediately, unless `wait: true` is passed, in which case we
  # wait for the server to agree.
  create: (model, options) ->
    options = (if options then _.clone(options) else {})
    return false  unless model = @_prepareModel(model, options)
    @add model, options  unless options.wait
    collection = this
    success = options.success
    options.success = (model, resp) ->
      collection.add model, options  if options.wait
      success model, resp, options  if success
      return

    model.save null, options
    model

  
  # **parse** converts a response into a list of models to be added to the
  # collection. The default implementation is just to pass it through.
  parse: (resp, options) ->
    resp

  
  # Create a new collection with an identical list of models as this one.
  clone: ->
    new @constructor(@models,
      model: @model
      comparator: @comparator
    )

  
  # Private method to reset all internal state. Called when the collection
  # is first initialized or reset.
  _reset: ->
    @length = 0
    @models = []
    @_byId = {}
    return

  
  # Prepare a hash of attributes (or other model) to be added to this
  # collection.
  _prepareModel: (attrs, options) ->
    if @_isModel(attrs)
      attrs.collection = this  unless attrs.collection
      return attrs
    options = (if options then _.clone(options) else {})
    options.collection = this
    model = new @model(attrs, options)
    return model  unless model.validationError
    @trigger "invalid", this, model.validationError, options
    false

  
  # Method for checking whether an object should be considered a model for
  # the purposes of adding to the collection.
  _isModel: (model) ->
    model instanceof Model

  
  # Internal method to create a model's ties to a collection.
  _addReference: (model, options) ->
    @_byId[model.cid] = model
    @_byId[model.id] = model  if model.id?
    model.on "all", @_onModelEvent, this
    return

  
  # Internal method to sever a model's ties to a collection.
  _removeReference: (model, options) ->
    delete model.collection  if this is model.collection
    model.off "all", @_onModelEvent, this
    return

  
  # Internal method called every time a model in the set fires an event.
  # Sets need to update their indexes when models change ids. All other
  # events simply proxy through. "add" and "remove" events that originate
  # in other collections are ignored.
  _onModelEvent: (event, model, collection, options) ->
    return  if (event is "add" or event is "remove") and collection isnt this
    @remove model, options  if event is "destroy"
    if model and event is "change:" + model.idAttribute
      delete @_byId[model.previous(model.idAttribute)]

      @_byId[model.id] = model  if model.id?
    @trigger.apply this, arguments
    return


# Underscore methods that we want to implement on the Collection.
# 90% of the core usefulness of Backbone Collections is actually implemented
# right here:
methods = [
  "forEach"
  "each"
  "map"
  "collect"
  "reduce"
  "foldl"
  "inject"
  "reduceRight"
  "foldr"
  "find"
  "detect"
  "filter"
  "select"
  "reject"
  "every"
  "all"
  "some"
  "any"
  "include"
  "contains"
  "invoke"
  "max"
  "min"
  "toArray"
  "size"
  "first"
  "head"
  "take"
  "initial"
  "rest"
  "tail"
  "drop"
  "last"
  "without"
  "difference"
  "indexOf"
  "shuffle"
  "lastIndexOf"
  "isEmpty"
  "chain"
  "sample"
  "partition"
]

# Mix in each Underscore method as a proxy to `Collection#models`.
_.each methods, (method) ->
  return  unless _[method]
  Collection::[method] = ->
    args = slice.call(arguments)
    args.unshift @models
    _[method].apply _, args

  return


# Underscore methods that take a property name as an argument.
attributeMethods = [
  "groupBy"
  "countBy"
  "sortBy"
  "indexBy"
]

# Use attributes instead of properties.
_.each attributeMethods, (method) ->
  return  unless _[method]
  Collection::[method] = (value, context) ->
    iterator = (if _.isFunction(value) then value else (model) ->
      model.get value
    )
    _[method] @models, iterator, context

  return


# Backbone.View
# -------------

# Backbone Views are almost more convention than they are actual code. A View
# is simply a JavaScript object that represents a logical chunk of UI in the
# DOM. This might be a single item, an entire list, a sidebar or panel, or
# even the surrounding frame which wraps your whole app. Defining a chunk of
# UI as a **View** allows you to define your DOM events declaratively, without
# having to worry about render order ... and makes it easy for the view to
# react to specific changes in the state of your models.

# Creating a Backbone.View creates its initial element outside of the DOM,
# if an existing element is not provided...
View = Backbone.View = (options) ->
  @cid = _.uniqueId("view")
  options or (options = {})
  _.extend this, _.pick(options, viewOptions)
  @_ensureElement()
  @initialize.apply this, arguments
  return


# Cached regex to split keys for `delegate`.
delegateEventSplitter = /^(\S+)\s*(.*)$/

# List of view options to be merged as properties.
viewOptions = [
  "model"
  "collection"
  "el"
  "id"
  "attributes"
  "className"
  "tagName"
  "events"
]

# Set up all inheritable **Backbone.View** properties and methods.
_.extend View::, Events,
  
  # The default `tagName` of a View's element is `"div"`.
  tagName: "div"
  
  # jQuery delegate for element lookup, scoped to DOM elements within the
  # current view. This should be preferred to global lookups where possible.
  $: (selector) ->
    @$el.find selector

  
  # Initialize is an empty function by default. Override it with your own
  # initialization logic.
  initialize: ->

  
  # **render** is the core function that your view should override, in order
  # to populate its element (`this.el`), with the appropriate HTML. The
  # convention is for **render** to always return `this`.
  render: ->
    this

  
  # Remove this view by taking the element out of the DOM, and removing any
  # applicable Backbone.Events listeners.
  remove: ->
    @_removeElement()
    @stopListening()
    this

  
  # Remove this view's element from the document and all event listeners
  # attached to it. Exposed for subclasses using an alternative DOM
  # manipulation API.
  _removeElement: ->
    @$el.remove()
    return

  
  # Change the view's element (`this.el` property) and re-delegate the
  # view's events on the new element.
  setElement: (element) ->
    @undelegateEvents()
    @_setElement element
    @delegateEvents()
    this

  
  # Creates the `this.el` and `this.$el` references for this view using the
  # given `el` and a hash of `attributes`. `el` can be a CSS selector or an
  # HTML string, a jQuery context or an element. Subclasses can override
  # this to utilize an alternative DOM manipulation API and are only required
  # to set the `this.el` property.
  _setElement: (el) ->
    @$el = (if el instanceof Backbone.$ then el else Backbone.$(el))
    @el = @$el[0]
    return

  
  # Set callbacks, where `this.events` is a hash of
  #
  # *{"event selector": "callback"}*
  #
  #     {
  #       'mousedown .title':  'edit',
  #       'click .button':     'save',
  #       'click .open':       function(e) { ... }
  #     }
  #
  # pairs. Callbacks will be bound to the view, with `this` set properly.
  # Uses event delegation for efficiency.
  # Omitting the selector binds the event to `this.el`.
  delegateEvents: (events) ->
    return this  unless events or (events = _.result(this, "events"))
    @undelegateEvents()
    for key of events
      method = events[key]
      method = this[events[key]]  unless _.isFunction(method)
      continue  unless method
      match = key.match(delegateEventSplitter)
      @delegate match[1], match[2], _.bind(method, this)
    this

  
  # Add a single event listener to the view's element (or a child element
  # using `selector`). This only works for delegate-able events: not `focus`,
  # `blur`, and not `change`, `submit`, and `reset` in Internet Explorer.
  delegate: (eventName, selector, listener) ->
    @$el.on eventName + ".delegateEvents" + @cid, selector, listener
    return

  
  # Clears all callbacks previously bound to the view by `delegateEvents`.
  # You usually don't need to use this, but may wish to if you have multiple
  # Backbone views attached to the same DOM element.
  undelegateEvents: ->
    @$el.off ".delegateEvents" + @cid  if @$el
    this

  
  # A finer-grained `undelegateEvents` for removing a single delegated event.
  # `selector` and `listener` are both optional.
  undelegate: (eventName, selector, listener) ->
    @$el.off eventName + ".delegateEvents" + @cid, selector, listener
    return

  
  # Produces a DOM element to be assigned to your view. Exposed for
  # subclasses using an alternative DOM manipulation API.
  _createElement: (tagName) ->
    document.createElement tagName

  
  # Ensure that the View has a DOM element to render into.
  # If `this.el` is a string, pass it through `$()`, take the first
  # matching element, and re-assign it to `el`. Otherwise, create
  # an element from the `id`, `className` and `tagName` properties.
  _ensureElement: ->
    unless @el
      attrs = _.extend({}, _.result(this, "attributes"))
      attrs.id = _.result(this, "id")  if @id
      attrs["class"] = _.result(this, "className")  if @className
      @setElement @_createElement(_.result(this, "tagName"))
      @_setAttributes attrs
    else
      @setElement _.result(this, "el")
    return

  
  # Set attributes from a hash on this view's element.  Exposed for
  # subclasses using an alternative DOM manipulation API.
  _setAttributes: (attributes) ->
    @$el.attr attributes
    return


# Backbone.sync
# -------------

# Override this function to change the manner in which Backbone persists
# models to the server. You will be passed the type of request, and the
# model in question. By default, makes a RESTful Ajax request
# to the model's `url()`. Some possible customizations could be:
#
# * Use `setTimeout` to batch rapid-fire updates into a single request.
# * Send up the models as XML instead of JSON.
# * Persist models via WebSockets instead of Ajax.
#
# Turn on `Backbone.emulateHTTP` in order to send `PUT` and `DELETE` requests
# as `POST`, with a `_method` parameter containing the true HTTP method,
# as well as all requests with the body as `application/x-www-form-urlencoded`
# instead of `application/json` with the model in a param named `model`.
# Useful when interfacing with server-side languages like **PHP** that make
# it difficult to read the body of `PUT` requests.
Backbone.sync = (method, model, options) ->
  type = methodMap[method]
  
  # Default options, unless specified.
  _.defaults options or (options = {}),
    emulateHTTP: Backbone.emulateHTTP
    emulateJSON: Backbone.emulateJSON

  
  # Default JSON-request options.
  params =
    type: type
    dataType: "json"

  
  # Ensure that we have a URL.
  params.url = _.result(model, "url") or urlError()  unless options.url
  
  # Ensure that we have the appropriate request data.
  if not options.data? and model and (method is "create" or method is "update" or method is "patch")
    params.contentType = "application/json"
    params.data = JSON.stringify(options.attrs or model.toJSON(options))
  
  # For older servers, emulate JSON by encoding the request into an HTML-form.
  if options.emulateJSON
    params.contentType = "application/x-www-form-urlencoded"
    params.data = (if params.data then model: params.data else {})
  
  # For older servers, emulate HTTP by mimicking the HTTP method with `_method`
  # And an `X-HTTP-Method-Override` header.
  if options.emulateHTTP and (type is "PUT" or type is "DELETE" or type is "PATCH")
    params.type = "POST"
    params.data._method = type  if options.emulateJSON
    beforeSend = options.beforeSend
    options.beforeSend = (xhr) ->
      xhr.setRequestHeader "X-HTTP-Method-Override", type
      beforeSend.apply this, arguments  if beforeSend
  
  # Don't process data on a non-GET request.
  params.processData = false  if params.type isnt "GET" and not options.emulateJSON
  
  # Pass along `textStatus` and `errorThrown` from jQuery.
  error = options.error
  options.error = (xhr, textStatus, errorThrown) ->
    options.textStatus = textStatus
    options.errorThrown = errorThrown
    error.apply this, arguments  if error
    return

  
  # Make the request, allowing the user to override any Ajax options.
  xhr = options.xhr = Backbone.ajax(_.extend(params, options))
  model.trigger "request", model, xhr, options
  xhr


# Map from CRUD to HTTP for our default `Backbone.sync` implementation.
methodMap =
  create: "POST"
  update: "PUT"
  patch: "PATCH"
  delete: "DELETE"
  read: "GET"


# Set the default implementation of `Backbone.ajax` to proxy through to `$`.
# Override this if you'd like to use a different library.
Backbone.ajax = ->
  Backbone.$.ajax.apply Backbone.$, arguments


# Backbone.Router
# ---------------

# Routers map faux-URLs to actions, and fire events when routes are
# matched. Creating a new one sets its `routes` hash, if not set statically.
Router = Backbone.Router = (options) ->
  options or (options = {})
  @routes = options.routes  if options.routes
  @_bindRoutes()
  @initialize.apply this, arguments
  return


# Cached regular expressions for matching named param parts and splatted
# parts of route strings.
optionalParam = /\((.*?)\)/g
namedParam = /(\(\?)?:\w+/g
splatParam = /\*\w+/g
escapeRegExp = /[\-{}\[\]+?.,\\\^$|#\s]/g

# Set up all inheritable **Backbone.Router** properties and methods.
_.extend Router::, Events,
  
  # Initialize is an empty function by default. Override it with your own
  # initialization logic.
  initialize: ->

  
  # Manually bind a single named route to a callback. For example:
  #
  #     this.route('search/:query/p:num', 'search', function(query, num) {
  #       ...
  #     });
  #
  route: (route, name, callback) ->
    route = @_routeToRegExp(route)  unless _.isRegExp(route)
    if _.isFunction(name)
      callback = name
      name = ""
    callback = this[name]  unless callback
    router = this
    Backbone.history.route route, (fragment) ->
      args = router._extractParameters(route, fragment)
      if router.execute(callback, args, name) isnt false
        router.trigger.apply router, ["route:" + name].concat(args)
        router.trigger "route", name, args
        Backbone.history.trigger "route", router, name, args
      return

    this

  
  # Execute a route handler with the provided parameters.  This is an
  # excellent place to do pre-route setup or post-route cleanup.
  execute: (callback, args, name) ->
    callback.apply this, args  if callback
    return

  
  # Simple proxy to `Backbone.history` to save a fragment into the history.
  navigate: (fragment, options) ->
    Backbone.history.navigate fragment, options
    this

  
  # Bind all defined routes to `Backbone.history`. We have to reverse the
  # order of the routes here to support behavior where the most general
  # routes can be defined at the bottom of the route map.
  _bindRoutes: ->
    return  unless @routes
    @routes = _.result(this, "routes")
    route = undefined
    routes = _.keys(@routes)
    @route route, @routes[route]  while (route = routes.pop())?
    return

  
  # Convert a route string into a regular expression, suitable for matching
  # against the current location hash.
  _routeToRegExp: (route) ->
    route = route.replace(escapeRegExp, "\\$&").replace(optionalParam, "(?:$1)?").replace(namedParam, (match, optional) ->
      (if optional then match else "([^/?]+)")
    ).replace(splatParam, "([^?]*?)")
    new RegExp("^" + route + "(?:\\?([\\s\\S]*))?$")

  
  # Given a route, and a URL fragment that it matches, return the array of
  # extracted decoded parameters. Empty or unmatched parameters will be
  # treated as `null` to normalize cross-browser behavior.
  _extractParameters: (route, fragment) ->
    params = route.exec(fragment).slice(1)
    _.map params, (param, i) ->
      
      # Don't decode the search params.
      return param or null  if i is params.length - 1
      (if param then decodeURIComponent(param) else null)



# Backbone.History
# ----------------

# Handles cross-browser history management, based on either
# [pushState](http://diveintohtml5.info/history.html) and real URLs, or
# [onhashchange](https://developer.mozilla.org/en-US/docs/DOM/window.onhashchange)
# and URL fragments. If the browser supports neither (old IE, natch),
# falls back to polling.
History = Backbone.History = ->
  @handlers = []
  _.bindAll this, "checkUrl"
  
  # Ensure that `History` can be used outside of the browser.
  if typeof window isnt "undefined"
    @location = window.location
    @history = window.history
  return


# Cached regex for stripping a leading hash/slash and trailing space.
routeStripper = /^[#\/]|\s+$/g

# Cached regex for stripping leading and trailing slashes.
rootStripper = /^\/+|\/+$/g

# Cached regex for stripping urls of hash.
pathStripper = /#.*$/

# Has the history handling already been started?
History.started = false

# Set up all inheritable **Backbone.History** properties and methods.
_.extend History::, Events,
  
  # The default interval to poll for hash changes, if necessary, is
  # twenty times a second.
  interval: 50
  
  # Are we at the app root?
  atRoot: ->
    path = @location.pathname.replace(/[^\/]$/, "$&/")
    path is @root and not @location.search

  
  # Gets the true hash value. Cannot use location.hash directly due to bug
  # in Firefox where location.hash will always be decoded.
  getHash: (window) ->
    match = (window or this).location.href.match(/#(.*)$/)
    (if match then match[1] else "")

  
  # Get the pathname and search params, without the root.
  getPath: ->
    path = decodeURI(@location.pathname + @location.search)
    root = @root.slice(0, -1)
    path = path.slice(root.length)  unless path.indexOf(root)
    path.slice 1

  
  # Get the cross-browser normalized URL fragment from the path or hash.
  getFragment: (fragment) ->
    unless fragment?
      if @_hasPushState or not @_wantsHashChange
        fragment = @getPath()
      else
        fragment = @getHash()
    fragment.replace routeStripper, ""

  
  # Start the hash change handling, returning `true` if the current URL matches
  # an existing route, and `false` otherwise.
  start: (options) ->
    throw new Error("Backbone.history has already been started")  if History.started
    History.started = true
    
    # Figure out the initial configuration. Do we need an iframe?
    # Is pushState desired ... is it available?
    @options = _.extend(
      root: "/"
    , @options, options)
    @root = @options.root
    @_wantsHashChange = @options.hashChange isnt false
    @_hasHashChange = "onhashchange" of window
    @_wantsPushState = !!@options.pushState
    @_hasPushState = !!(@options.pushState and @history and @history.pushState)
    @fragment = @getFragment()
    
    # Add a cross-platform `addEventListener` shim for older browsers.
    addEventListener = window.addEventListener or (eventName, listener) ->
      attachEvent "on" + eventName, listener

    
    # Normalize root to always include a leading and trailing slash.
    @root = ("/" + @root + "/").replace(rootStripper, "/")
    
    # Proxy an iframe to handle location events if the browser doesn't
    # support the `hashchange` event, HTML5 history, or the user wants
    # `hashChange` but not `pushState`.
    if not @_hasHashChange and @_wantsHashChange and (not @_wantsPushState or not @_hasPushState)
      iframe = document.createElement("iframe")
      iframe.src = "javascript:0"
      iframe.style.display = "none"
      iframe.tabIndex = -1
      body = document.body
      
      # Using `appendChild` will throw on IE < 9 if the document is not ready.
      @iframe = body.insertBefore(iframe, body.firstChild).contentWindow
      @navigate @fragment
    
    # Depending on whether we're using pushState or hashes, and whether
    # 'onhashchange' is supported, determine how we check the URL state.
    if @_hasPushState
      addEventListener "popstate", @checkUrl, false
    else if @_wantsHashChange and @_hasHashChange and not @iframe
      addEventListener "hashchange", @checkUrl, false
    else @_checkUrlInterval = setInterval(@checkUrl, @interval)  if @_wantsHashChange
    
    # Transition from hashChange to pushState or vice versa if both are
    # requested.
    if @_wantsHashChange and @_wantsPushState
      
      # If we've started off with a route from a `pushState`-enabled
      # browser, but we're currently in a browser that doesn't support it...
      if not @_hasPushState and not @atRoot()
        @location.replace @root + "#" + @getPath()
        
        # Return immediately as browser will do redirect to new url
        return true
      
      # Or if we've started out with a hash-based route, but we're currently
      # in a browser where it could be `pushState`-based instead...
      else if @_hasPushState and @atRoot()
        @navigate @getHash(),
          replace: true

    @loadUrl()  unless @options.silent

  
  # Disable Backbone.history, perhaps temporarily. Not useful in a real app,
  # but possibly useful for unit testing Routers.
  stop: ->
    
    # Add a cross-platform `removeEventListener` shim for older browsers.
    removeEventListener = window.removeEventListener or (eventName, listener) ->
      detachEvent "on" + eventName, listener

    
    # Remove window listeners.
    if @_hasPushState
      removeEventListener "popstate", @checkUrl, false
    else removeEventListener "hashchange", @checkUrl, false  if @_wantsHashChange and @_hasHashChange and not @iframe
    
    # Clean up the iframe if necessary.
    if @iframe
      document.body.removeChild @iframe.frameElement
      @iframe = null
    
    # Some environments will throw when clearing an undefined interval.
    clearInterval @_checkUrlInterval  if @_checkUrlInterval
    History.started = false
    return

  
  # Add a route to be tested when the fragment changes. Routes added later
  # may override previous routes.
  route: (route, callback) ->
    @handlers.unshift
      route: route
      callback: callback

    return

  
  # Checks the current URL to see if it has changed, and if it has,
  # calls `loadUrl`, normalizing across the hidden iframe.
  checkUrl: (e) ->
    current = @getFragment()
    current = @getHash(@iframe)  if current is @fragment and @iframe
    return false  if current is @fragment
    @navigate current  if @iframe
    @loadUrl()
    return

  
  # Attempt to load the current URL fragment. If a route succeeds with a
  # match, returns `true`. If no defined routes matches the fragment,
  # returns `false`.
  loadUrl: (fragment) ->
    fragment = @fragment = @getFragment(fragment)
    _.any @handlers, (handler) ->
      if handler.route.test(fragment)
        handler.callback fragment
        true


  
  # Save a fragment into the hash history, or replace the URL state if the
  # 'replace' option is passed. You are responsible for properly URL-encoding
  # the fragment in advance.
  #
  # The options object can contain `trigger: true` if you wish to have the
  # route callback be fired (not usually desirable), or `replace: true`, if
  # you wish to modify the current URL without adding an entry to the history.
  navigate: (fragment, options) ->
    return false  unless History.started
    options = trigger: !!options  if not options or options is true
    url = @root + (fragment = @getFragment(fragment or ""))
    
    # Strip the hash and decode for matching.
    fragment = decodeURI(fragment.replace(pathStripper, ""))
    return  if @fragment is fragment
    @fragment = fragment
    
    # Don't include a trailing slash on the root.
    url = url.slice(0, -1)  if fragment is "" and url isnt "/"
    
    # If pushState is available, we use it to set the fragment as a real URL.
    if @_hasPushState
      @history[(if options.replace then "replaceState" else "pushState")] {}, document.title, url
    
    # If hash changes haven't been explicitly disabled, update the hash
    # fragment to store history.
    else if @_wantsHashChange
      @_updateHash @location, fragment, options.replace
      if @iframe and (fragment isnt @getHash(@iframe))
        
        # Opening and closing the iframe tricks IE7 and earlier to push a
        # history entry on hash-tag change.  When replace is true, we don't
        # want this.
        @iframe.document.open().close()  unless options.replace
        @_updateHash @iframe.location, fragment, options.replace
    
    # If you've told us that you explicitly don't want fallback hashchange-
    # based history, then `navigate` becomes a page refresh.
    else
      return @location.assign(url)
    @loadUrl fragment  if options.trigger

  
  # Update the hash location, either replacing the current entry, or adding
  # a new one to the browser history.
  _updateHash: (location, fragment, replace) ->
    if replace
      href = location.href.replace(/(javascript:|#).*$/, "")
      location.replace href + "#" + fragment
    else
      
      # Some browsers require that `hash` contains a leading #.
      location.hash = "#" + fragment
    return


# Create the default Backbone.history.
Backbone.history = new History

# Helpers
# -------

# Helper function to correctly set up the prototype chain, for subclasses.
# Similar to `goog.inherits`, but uses a hash of prototype properties and
# class properties to be extended.
extend = (protoProps, staticProps) ->
  parent = this
  child = undefined
  
  # The constructor function for the new subclass is either defined by you
  # (the "constructor" property in your `extend` definition), or defaulted
  # by us to simply call the parent's constructor.
  if protoProps and _.has(protoProps, "constructor")
    child = protoProps.constructor
  else
    child = ->
      parent.apply this, arguments
  
  # Add static properties to the constructor function, if supplied.
  _.extend child, parent, staticProps
  
  # Set the prototype chain to inherit from `parent`, without calling
  # `parent`'s constructor function.
  Surrogate = ->
    @constructor = child
    return

  Surrogate:: = parent::
  child:: = new Surrogate
  
  # Add prototype properties (instance properties) to the subclass,
  # if supplied.
  _.extend child::, protoProps  if protoProps
  
  # Set a convenience property in case the parent's prototype is needed
  # later.
  child.__super__ = parent::
  child


# Set up inheritance for the model, collection, router, view and history.
Model.extend = Collection.extend = Router.extend = View.extend = History.extend = extend

# Throw an error when a URL is needed, and none is supplied.
urlError = ->
  throw new Error("A \"url\" property or function must be specified")


# Wrap an optional error callback with a fallback error event.
wrapError = (model, options) ->
  error = options.error
  options.error = (resp) ->
    error model, resp, options  if error
    model.trigger "error", model, resp, options
