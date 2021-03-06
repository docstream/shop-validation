Joi = require 'joi'
_ = require 'lodash'
assert = require 'assert'

# NB!!!! ClientSide and ServerSide  code
# TODO -> pack for web w/ webpack OR browserify

# export candidates -------------

# Event -> boolean
isContextEvent = (ev) ->
  !(Joi.validate ev.type, baseSchemas.ctxType).error

reducers =

  # dueDate

  # [Event] -> Int
  sumOfIncrements : (events) ->
    _.reduce events, ((sum,ev) ->
      if ev.type == 'incr-member-cap'
        sum + ev.increment
      else
        sum
    ),0

  # [Event] -> [ids] -> [ids]
  sqashedMembers : (events, members=[]) ->
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

validCtxTypes = ['account','trial','student']

baseSchemas =
  'ctxType' : Joi.string().only validCtxTypes

  'context' :  Joi.object().keys
    type: Joi.string().only validCtxTypes

  'org' : Joi.object().keys
    name: Joi.string().required()
    phone: Joi.string()
    addressLine1: Joi.string().required()
    addressLine2: Joi.string()
    city: Joi.string().required()
    zip: Joi.string().required()
    region: Joi.string()
    country: Joi.string().required()

  'user' : Joi.object().keys
    id: Joi.string().required()
    name: Joi.string().required()

# only whats needed here, can have MORE !!
orderStateSchema = Joi.object().keys {
    memberCapacity: Joi.number().integer()
    memberSet: Joi.array().items baseSchemas.user
    context: baseSchemas.context
  }
  .with 'memberSet', 'memberCapacity'


# [{}]
eventSchemas =

  # ----------------------------------------
  # -------------- E V E N T S  ------------
  # ----------------------------------------
  # make-sure-NO-overlapping-names
  #   since we are y = joiflattening inside SNAPSHOTS

  # genesis
  'account' : Joi.object().keys
    type: Joi.string().required().only 'account'
    org: baseSchemas.org # optional

  'incr-member-cap' : Joi.object().keys
    type: Joi.string().required().only 'incr-member-cap'
    increment: Joi.number().integer()

  'push-members' : Joi.object().keys
    type: Joi.string().required().only 'push-members'
    members: Joi.array().items baseSchemas.user

  'pop-members' : Joi.object().keys
    type: Joi.string().required().only 'pop-members'
    members: Joi.array().items baseSchemas.user

  # genesis
  'student' : Joi.object().keys
    type: Joi.string().required().only 'student'
    university: Joi.string().required()
    course: Joi.string().required()
    finishingYear: Joi.number().integer()

  # genesis
  'trial' : Joi.object().keys
    type: Joi.string().required().only 'trial'
    days: Joi.number().integer().required() # FIXME Security!!! Not allow hacking this!!!

  'cancel' : Joi.object().keys
    type: Joi.string().required().only 'cancel'
    msg: Joi.string().required()

  'uncancel' : Joi.object().keys
    type: Joi.string().required().only 'uncancel'
    msg: Joi.string().required()

  # TEST!
  'noop' : Joi.any()


# challenge the STATE aka state !
checkOrderingRules = (event, precedingEvents, state) ->

  #console.log "precedingEvents",precedingEvents

  # SENTINEL helper
  # context -> Either<Err,Void>
  mustBelongToContextType = (contextType) ->
    Joi.attempt contextType, baseSchemas.ctxType
    errMsg = "context-type different than '#{contextType}' !"
    if precedingEvents.length>0 and state?.context?.type != contextType
      rule = _.some precedingEvents, (pEv) -> pEv.type == contextType
      assert rule, errMsg
    else if state?.context?.type != contextType
      console.warn '>>>> STRANGE snap=',state
      assert.fail errMsg

  cancelled = ->
    prevCancelEv = _.find precedingEvents.reverse(), (ev) ->
      ev.type == 'cancel' or ev.type == 'uncancel'
    if prevCancelEv
      cancelled: prevCancelEv.type == 'cancel' or false
      msg: prevCancelEv.cancelMsg
    else
      cancelled: state.cancelled
      msg: state.cancelMsg



   # SENTINEL helper
  cannotConflictEarlierContext = (contextTypes) ->
    _.each contextTypes, (t) ->
      Joi.attempt t, baseSchemas.ctxType

    precedingType = (_.find precedingEvents, isContextEvent)?.type
    earliestContext = state?.context?.type or precedingType
    if earliestContext and not (earliestContext in contextTypes)
      assert.fail "Cannot [#{event.type}] now.\n
       \\_ [context] missmatch since '#{earliestContext}' is our context!"

  currCap = ->
    (state.memberCapacity or 0) + (reducers.sumOfIncrements precedingEvents)

  accumulatedMembers = ->
    precedingMems = reducers.sqashedMembers precedingEvents
    console.log "Calculated; precedingMems #{precedingMems}"

    # NOTE above is not ROCK-SOLID !!! since each PREV could have .error={} by now
    _.union precedingMems, event.members, state.memberSet

  {
    'account' :  ->
      cannotConflictEarlierContext ['account','trial']

    'trial' :  ->
      cannotConflictEarlierContext ['trial']

    'student' :  ->
      cannotConflictEarlierContext ['student']

    'incr-member-cap' :  ->
      mustBelongToContextType 'account'

      currCap_ = currCap()
      console.log "Calculated; currCap #{currCap_}"
      newCap = currCap_ + event.increment
      console.log "Calculated; newCap #{newCap}"
      accumulatedMembers_ = accumulatedMembers()
      console.log "Calculated; accumulatedMembers #{accumulatedMembers_}"

      errMsg = "Cannot [#{event.type}] now.
        Cap try [#{newCap}] but mem-cnt is [#{accumulatedMembers_.length}]"
      assert newCap >= accumulatedMembers_.length, errMsg


    'push-members' :  ->
      # rule 1
      mustBelongToContextType 'account'

      console.log "state MEMz >", state.memberSet
      currCap_ = currCap()
      console.log "Calculated; currCap #{currCap_}"

      accumulatedMembers_ = accumulatedMembers()
      console.log "Calculated; accumulatedMembers #{accumulatedMembers_}"

      errMsg = "Cannot [#{event.type}] now. OVERFLOW ! capacity = #{currCap_}"
      assert currCap_ >= accumulatedMembers_.length, errMsg

    'pop-members' :  ->
      # rule 1
      mustBelongToContextType 'account'

      # rule 2
      currMembers = reducers.sqashedMembers precedingEvents, state.memberSet
      # NOTE above is not ROCK-SOLID !!! since each PREV could have .error={} by now
      diff = _.difference event.members, currMembers

      errMsg = "Cannot [#{event.type}] now. Cannot pop NON-EXISTING members; #{diff}"
      assert diff.length == 1, errMsg #NOTE Was diff.length == 0

    'cancel' : ->
      assert not cancelled().cancelled, 'Order is ALREADY cancelled !'
    'uncancel': ->
      assert cancelled().cancelled, 'Order dont NEED un-cancelling !'
  }


# Sync
# state = {shop-state}
# data = [events..]
# returns VOID
# throws
#   err = { .data=annotated-data-clone } instanceOf Error
validate = (state, data ) ->

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

module.exports =
  validate: validate
  reducers: reducers
