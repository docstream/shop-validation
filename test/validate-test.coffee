assert = require 'assert'
shoudl = require 'should'
_ =  require 'lodash'

describe 'state validation', ->

  validate = sut = require '../index.coffee'
  fix = require './ev-fixture.coffee'

  snapshot =
     idx: 1000

  it 'has ISSUES on push-mem without CAP', (done) ->

    data = [
      fix.acc(), fix.pushM(2)
    ]

    should.throws ( ->
      validate snapshot, data),
    (err) ->
      d = err.data
      should( d[0].errors ).not.be
      d[1].errors.length.should.eql 1
      d[1].errors[0].message.should.match /OVERFLOW/
      done()


  it 'has ISSUES if pop-mem not-existing', (done) ->

    data = [
      fix.acc(), fix.popM(4)
    ]

    should.throws (->
      validate snapshot, data),
    (err) ->
      d = err.data
      should( d[0].errors ).not.be
      d[1].errors.length.should.eql 1
      msg_ = d[1].errors[0].message
      console.log 'd[1].errors[0].message', msg_
      msg_.should.match /Cannot pop NON-EXISTING/
      done()

  it 'WORKS if push-mem after increment', ->

    data = [
      fix.acc(), fix.incrCap(555) , fix.pushM(500), fix.pushM(55)
    ]

    # thows if invalid data!
    validate snapshot, data

  it 'will not handle crazy events', (done) ->

    data = [
      { type: 'crazy', just: "a-hack"}
    ]


    should.throws (->
      validate snapshot, data),
    (err) ->
      d = err.data
      should( d[0].errors ).not.be
      done()
   


  it 'has ISSUES on trial AFTER account', (done) ->

    data = [
      fix.acc(), fix.acc(), fix.trial()
    ]

    should.throws (->
      validate snapshot, data),
    (err) ->
      d = err.data
      should( d[0].errors ).not.be
      should( d[1].errors ).not.be
      d[2].errors.length.should.eql 1
      msg_ = d[2].errors[0].message
      console.log 'd[2].errors[0].message', msg_
      msg_.should.match /missmatch since 'account'/
      done()