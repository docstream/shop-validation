assert = require 'assert'
should = require 'should'
_ =  require 'lodash'

describe 'validation', ->

  sut = require '../index.coffee'
  fix = require './ev-fixture.coffee'

  # S T A T E
  #
  #
  #
  #

  describe 'state', ->

    it 'fails if STRANGE .context', (done) ->

      state2 =
       context:
        type:'x'

      data = [ {} ] # not important

      should.throws (->
        sut.validate state2 , data),
      (err) ->
        err.message.should.match /"type" must be one of/
        done()

    it 'fails if .members without .memberCapacity', (done) ->

      state2 =
       context: 
        type : 'account'
       memberSet: ['xxx']

      data = [ {} ] # not important

      should.throws (->
        sut.validate state2 , data),
      (err) ->
        err.message.should.match /"memberSet" missing required peer/
        done()

    it 'fails if bad props', (done) ->

      state2 =
       context: 
         type: 'account'
       memberCapacity: 'text'

      data = [ {} ] # not important

      should.throws (->
        sut.validate state2 , data),
      (err) ->
        err.message.should.match /"memberCapacity" must be a number/
        done()



  # events
  #
  #
  #
  #


  describe 'data - event combos', ->

    state = {}

    it 'has ISSUES on push-mem without CAP set', (done) ->

      data = [
        fix.acc()
        fix.pushM(2)
      ]

      should.throws ( ->
        sut.validate state, data),
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
        sut.validate state, data),
      (err) ->
        d = err.data
        should( d[0].error ).not.be
        d[1].error.should.be
        msg_ = d[1].error.message
        msg_.should.match /Cannot pop NON-EXISTING/
        done()



    it 'has no issues on pushMem if context set in snap', (done) ->

      data = [
        # neither account|trial|student
        fix.incrCap 1111
      ]

      state2 =
       idx: 42
       context: 
         type: 'account' 

      # 1
      sut.validate state2 , data
      done()

    it 'handles student context', (done) ->

      data = [
        fix.student()
      ]

      # 1
      sut.validate state , data
      done()

     it 'has ISSUES w context other than account if CAP incr', (done) ->

      data = [
        # neither account|trial|student
        fix.incrCap 1111
      ]

      state2 =
       idx: 42
       context: 
         type:'trial' 

      # 1
      should.throws (->
        sut.validate state, data),
      (err) ->
        d = err.data
        d[0].error.message.should.match /context-type different than/
        done()

    it 'RULES part not avail for NOOP ;;; coverage-max loophole', (done) ->

      data = [
        {type:'noop'}
      ]

      should.throws (->
        sut.validate state , data),
      (err) ->
        d = err.data   
        d[0].error.message.should.match /Rules for event \[\[noop\] 0\] missing/
        done()


    it 'WORKS if pop-mem on Mem set', (done) ->

      data = [
        fix.trial()
        fix.acc()
        fix.incrCap 111
        fix.pushM 5
        fix.popM 4 # 1 left
        fix.popM 1 # 0 left
      ]

      sut.validate state, data
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
      sut.validate state, data
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

      sut.validate state, data
      done()

    it 'has ISSUES if push-mem but LOW STATE cap', (done) ->

      state_ =
        idx: 1
        context: 
          type:'account'
        memberCapacity: 1

      data = [ fix.pushM 2 ]

      should.throws ( ->
        sut.validate state_, data),
      (err) ->
        d = err.data   
        d[0].error.message.should.match /OVERFLOW/
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
        sut.validate state, data),
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
        sut.validate state, data),
      (err) ->
        d = err.data
        d[0].error.should.be
        d[0].error.message.match /schema.*missing/
        done()

    it 'will not handle JOI-invalid events, props missing', (done) ->

      data = [
        { type: 'trial' }   # .days missing
        { type: 'student' } # .university missing
      ]

      should.throws (->
        sut.validate state, data),
      (err) ->
        d = err.data
        d[0].error.should.be
        d[1].error.should.be

        d[0].error.isJoi.should.be.ok
        d[1].error.isJoi.should.be.ok

        d[0].error.message.should.match /"days" is required/
        d[1].error.message.should.match /"university" is required/

        done()


    it 'has ISSUES on trial AFTER account', (done) ->

      data = [
        fix.acc(), fix.acc(), fix.trial()
      ]

      should.throws (->
        sut.validate state, data),
      (err) ->
        d = err.data
        should( d[0].error ).not.be
        should( d[1].error ).not.be
        d[2].error.should.be
        msg_ = d[2].error.message
        msg_.should.match /missmatch since 'account'/
        done()