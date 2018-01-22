assert = require 'assert'
shoudl = require 'should'
_ =  require 'lodash'

describe 'state validation', ->

  validate = sut = require '../index.coffee'
  fix = require './ev-fixture.coffee'

  snapshot =
     idx: 1000

  it 'has ISSUES on push-mem without CAP set', (done) ->

    data = [
      fix.acc()
      fix.pushM(2)
    ]

    should.throws ( ->
      validate snapshot, data),
    (err) ->
      d = err.data
      should( d[0].errors ).not.be
      d[1].error.should.be
      d[1].error.message.should.match /OVERFLOW/
      done()


  it 'has ISSUES if pop-mem not-existing', (done) ->

    data = [
      fix.acc()
      fix.popM(4)
    ]

    should.throws (->
      validate snapshot, data),
    (err) ->
      d = err.data
      should( d[0].error ).not.be
      d[1].error.should.be
      msg_ = d[1].error.message
      msg_.should.match /Cannot pop NON-EXISTING/
      done()

  it 'has ISSUES on pushMem if STRANGE subscriberType', (done) ->

    data = [
      # neither account|trial|student
      fix.pushM 1
    ]

    snapshot2 =
     idx: 42
     subscriberType: 'x'

    should.throws (->
      validate snapshot2 , data),
    (err) ->
      d = err.data
      msg_ = d[0].error.message
      msg_.should.match /isnt \'account\'/
      done()

  it 'has no issues on pushMem if subscriberType set in snap', (done) ->

    data = [
      # neither account|trial|student
      fix.incrCap 1111
    ]

    snapshot2 =
     idx: 42
     subscriberType: 'account' 

    # 1

    validate snapshot2 , data
    done()

  it 'RULES part not avail for NOOP ;;; coverage-max loophole', (done) ->

    data = [
      {type:'noop'}
    ]

    should.throws (->
      validate snapshot , data),
    (err) ->
      d = err.data   
      d[0].error.message.should.match /Rules for event \[noop\] missing/
      done()


  it 'WORKS if pop-mem on Mem set', (done) ->

    data = [
      fix.acc()
      fix.incrCap 111
      fix.pushM 5
      fix.popM 4 # 1 left
      fix.popM 1 # 0 left
    ]

    validate snapshot, data
    done()


  it 'WORKS if push-mem after increment', (done) ->

    data = [
      fix.acc()
      fix.incrCap 5
      fix.pushM 1 # just to make u think
      fix.pushM 1 # just to make u think
      fix.pushM 5
    ]

    # thows if invalid data!
    validate snapshot, data
    done()

  it 'has NO issues if push-mem (SAME ID UNION) but LOW CAP', (done) ->

    data = [
      fix.acc()
      fix.incrCap 5
      fix.pushM 4 # 4x ids from seq
      fix.pushM 1 # 1st-id again
      fix.pushM 2 # 1st-id 2nd-id again
      fix.pushM 4 # 1st-id 2nd-id 3rd-id 4th-id again
    ]

    validate snapshot, data
    done()
    

  it 'has ISSUES if push-mem(new IDs) but LOW CAP', (done) ->

    data = [
      fix.acc()
      fix.incrCap 6
      fix.pushM 5  # 5x ids from seq
      fix.pushM ['idX|not-in-prev-set' , 'idX|ANOTHER-not-in-prev-set' ]
      fix.pushM ['idY|same' , 'idY|same-same' ]
    ]

    should.throws (->
      validate snapshot, data),
    (err) ->
      d = err.data
      err.message.should.match /2 issue\(s\)/
      d[3].error.should.be
      d[4].error.should.be
      done()

  it 'will not handle crazy events', (done) ->

    data = [
      { type: 'crazy', just: "a-hack"}
    ]

    should.throws (->
      validate snapshot, data),
    (err) ->
      d = err.data
      d[0].error.should.be
      d[0].error.message.match /schema.*missing/
      done()

  it 'will not handle invalid events, props missing', (done) ->

    data = [
      { type: 'account' } # .name missing
    ]

    should.throws (->
      validate snapshot, data),
    (err) ->
      d = err.data
      d[0].error.should.be
      d[0].error.isJoi.should.be.ok
      d[0].error.message.should.match /"name" is required/
      done()


  it 'has ISSUES on trial AFTER account', (done) ->

    data = [
      fix.acc(), fix.acc(), fix.trial()
    ]

    should.throws (->
      validate snapshot, data),
    (err) ->
      d = err.data
      should( d[0].error ).not.be
      should( d[1].error ).not.be
      d[2].error.should.be
      msg_ = d[2].error.message
      msg_.should.match /missmatch since 'account'/
      done()