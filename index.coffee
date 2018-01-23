Joi = require 'joi'
_ = require 'lodash'
assert = require 'assert'

# ClientSide and ServerSide 

# NB NB Compile-down! (no Promises)

# export candidates -------------

# SCHEMAs

# event.types valid as CONTEXT
contextType = Joi.string().only ['account','trial','student']

universityType = Joi.object().keys
  name: Joi.string().required()
  course: Joi.string().required()
  finishingYear: Joi.string().required()

billingAddressType = Joi.object().keys
  addressLine1: Joi.string().required()
  addressLine2: Joi.string()
  city: Joi.string().required()
  zip: Joi.string().required()
  region: Joi.string()
  country: Joi.string()

snapshotType = Joi.object().keys {
    productID: Joi.string()
    ownerID: Joi.string()
    idx: Joi.number().integer()
    # --------------------------------------
    context: contextType
    modified: Joi.date()
    modifierId: Joi.string()
    # ------------- common unless [trial]
    name: Joi.string()
    phone: Joi.string()
    #-------------- account (normal)
    memberCapacity: Joi.number().integer()
    billingAddress: billingAddressType
    members: Joi.array().items Joi.string()
    # ------------- student
    university: universityType
    # ------------- trial
    days: Joi.number().integer()
  }
  # typical CONTEXT trails 
  .with 'members', ['memberCapacity','billingAddress'] 
  .without 'days', ['billingAddress','university'] # ? 'name','phone'
  .without 'university', ['billingAddress','days']



# Event -> boolean
isContextEvent = (ev) ->
  !(Joi.validate ev.type, contextType).error

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


# [{}] 
evSchemas =

  # genesis
  'account' : Joi.object().keys
    type: Joi.string().required().only 'account'
    name: Joi.string().required()
    phone: Joi.string()
    billingAddress: billingAddressType

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
    name: Joi.string().required()
    phone: Joi.string()
    university: universityType

  # genesis
  'trial' : Joi.object().keys
    type: Joi.string().required().only 'trial'
    days: Joi.number().integer()

  # TEST!
  'noop' : Joi.any()


# challenge the STATE aka snapshot !
checkOrderingRules = (event, precedingEvents, snapshot) ->

  #console.log "precedingEvents",precedingEvents

  # SENTINEL helper
  # context -> Either<Err,Void>
  mustBelongToContext = (context) ->
    Joi.attempt context, contextType
    errMsg = "context different than '#{context}' !"
    if precedingEvents.length>0 and snapshot.context != context
      rule = _.some precedingEvents, (pEv) -> pEv.type == context
      assert rule, errMsg
    else if snapshot.context != context
      console.warn '>>>> STRANGE snap=',snapshot
      assert.fail errMsg

   # SENTINEL helper
  cannotConflictEarlierContext = (context) ->
    Joi.attempt context, contextType
    precedingType = (_.find precedingEvents, isContextEvent)?.type
    earliestContext = snapshot.context or precedingType
    if earliestContext and earliestContext != context
      assert.fail "Cannot [#{event.type}] now.\n
       \\_ [context] missmatch since '#{earliestContext}' is our context!"

  {
    'account' :  ->
      cannotConflictEarlierContext 'account'
     
    'trial' :  ->
      cannotConflictEarlierContext 'trial'

    'university' :  ->
      cannotConflictEarlierContext 'university'
      
    'incr-member-cap' :  ->
      mustBelongToContext 'account'
      # TODO max-min check?

    'push-members' :  ->
      # rule 1
      mustBelongToContext 'account'

      # rule 2
      currCap = currentMemberCapacity precedingEvents, snapshot.memberCapacity
      precedingMems = sqashedMembers precedingEvents
      # NOTE above is not ROCK-SOLID !!! since each PREV could have .error={} by now
      accumulatedMembers = _.union precedingMems, event.members
      
      errMsg = "Cannot [#{event.type}] now. OVERFLOW ! capacity = #{currCap}"
      assert currCap >= accumulatedMembers.length, errMsg

    'pop-members' :  ->
      # rule 1
      mustBelongToContext 'account'

      # rule 2
      currMembers = sqashedMembers precedingEvents, snapshot.members
      # NOTE above is not ROCK-SOLID !!! since each PREV could have .error={} by now
      diff = _.difference event.members, currMembers
      errMsg = "Cannot [#{event.type}] now. Cannot pop NON-EXISTING members; #{diff}"
      assert diff.length == 0, errMsg
  }


# Sync
# snapshot = {shop-state}
# data = [events..]
# returns VOID
# throws
#   err = { .data=annotated-data-clone } instanceOf Error
module.exports = validate = (snapshot, data ) ->

  # state
  errs = 0

  Joi.attempt snapshot, snapshotType

  # mutator/helper
  appendErr = (event,err) ->
    event.error = err
    errs += 1
    event

  # mutates !
  annotatedData = _.map data, (ev,idx) ->

    ev_ = _.cloneDeep ev

    unless (_.has evSchemas, ev.type)
      err = new Error "BUG!!! Schema for event [#{ev.type}] missing!"
      return appendErr ev,err
   
    console.log "Schema; found for [#{ev.type}]"
    
    vStat = Joi.validate ev, evSchemas[ev.type]
    return appendErr ev, vStat.error if vStat.error
    
    console.log "Joi-valid; [#{ev.type}] = ", vStat?.error?.message or 'passed'

    precedingEvents = data[0...idx]
    checkers = checkOrderingRules ev,precedingEvents,snapshot
    
    unless (_.has checkers, ev.type)
      err = new Error "BUG!!! Rules for event [#{ev.type}] missing!"
      return appendErr ev,err

    try
      checkers[ev.type]()
      console.log "rules-check; [#{ev.type}] = passed"
      ev_ # no errors
    catch err
      console.log "rules-check; [#{ev.type}] = ",err.message
      return appendErr ev,err
    

  if errs > 0
    err = new Error "Found #{errs} issue(s)"
    err.data = annotatedData
    throw err