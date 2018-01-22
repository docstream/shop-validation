Joi = require 'joi'
_ = require 'lodash'
assert = require 'assert'



# ClientSide and ServerSide 

# NB NB Compile-down! (no Promises)



# export candidates -------------

# SCHEMA
subscriberType = Joi.string().required().only ['account','trial','student']

# Event -> boolean
isSubscriberTypeEvent = (ev) ->
  !(Joi.validate ev.type, subscriberType).error

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

  # subscriper-type
  'account' : Joi.object().keys
    type: Joi.string().required().only 'account'
    name: Joi.string().required()
    phone: Joi.string()
    billingAddress: Joi.object().keys
      addressLine1: Joi.string().required()
      addressLine2: Joi.string()
      city: Joi.string().required()
      zip: Joi.string().required()
      region: Joi.string()
      country: Joi.string()

  'incr-member-cap' :
    type: Joi.string().required().only 'incr-member-cap'
    increment: Joi.number().integer()

  'push-members' : Joi.object().keys
    type: Joi.string().required().only 'push-members'
    members: Joi.array().items Joi.string()

  'pop-members' : Joi.object().keys
    type: Joi.string().required().only 'pop-members'
    members: Joi.array().items Joi.string()

  # subscriper-type
  'student' : Joi.object().keys
    type: Joi.string().required().only 'student'
    name: Joi.string().required()
    phone: Joi.string()
    univerity: Joi.object().keys
      name: Joi.string().required()
      course: Joi.string().required()
      finishingYear: Joi.string().required()

  # subscriper-type
  'trial' : Joi.object().keys
    type: Joi.string().required().only 'trial'
    days: Joi.number().integer()


# challenge the STATE aka snapshot !
checkOrderingRules = (event, precedingEvents, snapshot) ->

  #console.log "precedingEvents",precedingEvents

  # SENTINEL helper
  # subscriberType -> Either<Err,Void>
  mustBelongToSubscriberType = (subsType) ->
    Joi.attempt subsType, subscriberType
    errMsg = "[.subscriberType] isnt '#{subsType}' !"
    if snapshot.subscriberType != subsType
      rule = _.some precedingEvents, (pEv) -> pEv.type == subsType
      assert rule, errMsg
    else
      assert.fail errMsg

   # SENTINEL helper
  cannotConflictEarlierSubscriberType = (subsType) ->
    Joi.attempt subsType, subscriberType
    precedingSubsType = (_.find precedingEvents, isSubscriberTypeEvent)?.type
    earliestSubsType = snapshot.subscriberType or precedingSubsType
    if earliestSubsType and earliestSubsType != subsType
      assert.fail "Cannot [#{event.type}] now.\n
       \\_ [subscriberType] missmatch since '#{earliestSubsType}' found!"

  {
    'account' :  ->
      cannotConflictEarlierSubscriberType 'account'
     
    'trial' :  ->
      cannotConflictEarlierSubscriberType 'trial'
      
    'incr-member-cap' :  ->
      mustBelongToSubscriberType 'account'
      # TODO max-min check?

    'push-members' :  ->
      # rule 1
      mustBelongToSubscriberType 'account'

      # rule 2
      currCap = currentMemberCapacity precedingEvents, snapshot.memberCapacity
      errMsg = "Cannot [#{event.type}] now. OVERFLOW ! capacity = #{currCap}"
      assert currCap >= event.members.length, errMsg

    'pop-members' :  ->
      # rule 1
      mustBelongToSubscriberType 'account'

      # rule 2
      currMembers = sqashedMembers precedingEvents, snapshot.members
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

  errs = 0

  # mutates !
  annotatedData = _.map data, (ev,idx) ->

    ev_ = _.cloneDeep ev

    assert (_.has evSchemas, ev.type) , "BUG!!! Schema for event [#{ev.type}] missing!"
    vStat = Joi.validate ev, evSchemas[ev.type]
    if vStat.error
      errs += 1
      ev_.errors = [vStat.error]

    console.log "Joi-valid; [#{ev.type}] = ", vStat?.error?.message or 'passed'

    precedingEvents = data[0...idx]
    checkers = checkOrderingRules ev,precedingEvents,snapshot
    assert (_.has checkers, ev.type) , "BUG!!! Rules for event [#{ev.type}] missing!"
    try
      checkers[ev.type]()
      console.log "rules-check; [#{ev.type}] = passed"
    catch err
      errs += 1
      ev_.errors = ev_.errors or []
      ev_.errors.push err
      console.log "rules-check; [#{ev.type}] = ",err.message

    ev_

  if errs > 0
    err = new Error "Found #{errs} issue(s)"
    err.data = annotatedData
    throw err
  else
    console.log "WUT?!"
