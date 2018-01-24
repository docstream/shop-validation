Joi = require 'joi'
_ = require 'lodash'
assert = require 'assert'

# NB!!!! ClientSide and ServerSide  code
# TODO -> pack for web w/ webpack OR browserify


# export candidates -------------

# Event -> boolean
isContextEvent = (ev) ->
  !(Joi.validate ev.type, baseSchemas.context).error

# [Event] -> Int
sumOfIncrements = (events) ->
  _.reduce events, ((sum,ev) ->
    if ev.type == 'incr-member-cap'
      sum + ev.increment
    else
      sum
  ),0

# [Event] -> Int -> Int
currentMemberCapacity = (events, cap=0) ->
  cap + (sumOfIncrements events)

# [Event] -> [ids] -> [ids]
sqashedMembers = (events, members=[]) ->
  _.reduce events, ((acc,ev) ->
    if ev.type == 'push-members'
      # add
      acc = _.union acc, ev.members
    else if ev.type == 'pop-members'
      # remove/pop
      acc = _.remove acc, (mem) ->
        mem in ev.members
    acc
  ), members


baseSchemas = 

  'context' :  Joi.string().only ['account','trial','student']

  'university' : Joi.object().keys
    name: Joi.string().required()
    course: Joi.string().required()
    finishingYear: Joi.number().integer()

  'org' : Joi.object().keys
    name: Joi.string().required()
    phone: Joi.string()
    addressLine1: Joi.string().required()
    addressLine2: Joi.string()
    city: Joi.string().required()
    zip: Joi.string().required()
    region: Joi.string()
    country: Joi.string().required()

# only whats needed here, can have MORE !!
orderStateSchema = Joi.object().keys {
    memberCapacity: Joi.number().integer()
    members: Joi.array().items Joi.string()
    context: baseSchemas.context
  }
  .with 'members', 'memberCapacity'


# [{}]
eventSchemas =

  # ----------------------------------------
  # -------------- E V E N T S  ------------
  # ----------------------------------------

  # genesis
  'account' : Joi.object().keys
    type: Joi.string().required().only 'account'
    org: baseSchemas.org # optional

  'incr-member-cap' : Joi.object().keys
    type: Joi.string().required().only 'incr-member-cap'
    increment: Joi.number().integer()

  'push-members' : Joi.object().keys
    type: Joi.string().required().only 'push-members'
    members: Joi.array().items Joi.string()

  'pop-members' : Joi.object().keys
    type: Joi.string().required().only 'pop-members'
    members: Joi.array().items Joi.string()

  # genesis
  'student' : Joi.object().keys
    type: Joi.string().required().only 'student'
    university: baseSchemas.university.required()

  # genesis
  'trial' : Joi.object().keys
    type: Joi.string().required().only 'trial'
    days: Joi.number().integer().required()

  # TEST!
  'noop' : Joi.any()


# challenge the STATE aka state !
checkOrderingRules = (event, precedingEvents, state) ->

  #console.log "precedingEvents",precedingEvents

  # SENTINEL helper
  # context -> Either<Err,Void>
  mustBelongToContext = (context) ->
    Joi.attempt context, baseSchemas.context
    errMsg = "context different than '#{context}' !"
    if precedingEvents.length>0 and state.context != context
      rule = _.some precedingEvents, (pEv) -> pEv.type == context
      assert rule, errMsg
    else if state.context != context
      console.warn '>>>> STRANGE snap=',state
      assert.fail errMsg

   # SENTINEL helper
  cannotConflictEarlierContext = (context) ->
    Joi.attempt context, baseSchemas.context
    precedingType = (_.find precedingEvents, isContextEvent)?.type
    earliestContext = state.context or precedingType
    if earliestContext and earliestContext != context
      assert.fail "Cannot [#{event.type}] now.\n
       \\_ [context] missmatch since '#{earliestContext}' is our context!"

  {
    'account' :  ->
      cannotConflictEarlierContext 'account'
     
    'trial' :  ->
      cannotConflictEarlierContext 'trial'

    'student' :  ->
      cannotConflictEarlierContext 'student'
      
    'incr-member-cap' :  ->
      mustBelongToContext 'account'
      # TODO max-min check?

    'push-members' :  ->
      # rule 1
      mustBelongToContext 'account'

      # rule 2
      currCap = currentMemberCapacity precedingEvents, state.memberCapacity
      precedingMems = sqashedMembers precedingEvents
      # NOTE above is not ROCK-SOLID !!! since each PREV could have .error={} by now
      accumulatedMembers = _.union precedingMems, event.members
      
      errMsg = "Cannot [#{event.type}] now. OVERFLOW ! capacity = #{currCap}"
      assert currCap >= accumulatedMembers.length, errMsg

    'pop-members' :  ->
      # rule 1
      mustBelongToContext 'account'

      # rule 2
      currMembers = sqashedMembers precedingEvents, state.members
      # NOTE above is not ROCK-SOLID !!! since each PREV could have .error={} by now
      diff = _.difference event.members, currMembers
      errMsg = "Cannot [#{event.type}] now. Cannot pop NON-EXISTING members; #{diff}"
      assert diff.length == 0, errMsg
  }


# Sync
# state = {shop-state}
# data = [events..]
# returns VOID
# throws
#   err = { .data=annotated-data-clone } instanceOf Error
module.exports = validate = (state, data ) ->

  # state
  fstErr = null
  errs = 0

  sRes = Joi.validate state, orderStateSchema, { allowUnknown:yes }
  if sRes.error
    console.log "[[[state]]]: INVALID (joi) ;", sRes.error.message
    throw sRes.error


  # mutator/helper
  appendErr = (event,err) ->
    event.error = err
    fstErr = fstErr or err
    errs += 1
    event

  # mutates !
  annotatedData = _.map data, (ev,idx) ->

    lineId_ = "[#{ev.type}] #{idx}"

    ev_ = _.cloneDeep ev

    unless (_.has eventSchemas, ev.type)
      err = new Error "BUG!!! Schema for event [#{lineId_}] missing!"
      return appendErr ev,err
    
    vRes = Joi.validate ev, eventSchemas[ev.type]
    if vRes.error
      console.log "#{lineId_}: INVALID (joi) ;", vRes.error.message
      return appendErr ev, vRes.error 
    
    console.log "#{lineId_}: passed joi "

    precedingEvents = data[0...idx]
    checkers = checkOrderingRules ev,precedingEvents,state
    
    unless (_.has checkers, ev.type)
      err = new Error "BUG!!! Rules for event [#{lineId_}] missing!"
      return appendErr ev,err

    try
      checkers[ev.type]()
      console.log "#{lineId_}: passed rules check"
      ev_ # no errors
    catch err
      console.log "#{lineId_}: FAILING rules check ;", err.message
      return appendErr ev,err

  if errs > 0
    err = new Error "Found #{errs} issue(s) | 1st err; #{fstErr.message}"
    err.data = annotatedData
    throw err