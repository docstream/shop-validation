#fixture
_ = require 'lodash'

module.exports = fix =

  
  members : [  
    'id1-doh'
    'id2-joh'
    'id3-geh'
    'id4-dee'
    'id5-sni'
  ]

  trial : ->
    type: 'trial'
    days: 500

  student : ->
    type: 'student'
    university: 'honolulu'
    course: 'eventSourcing'
    finishingYear: 3001

  acc : ->
    type: 'account'
    org: 
      organization: 'PER AS'
      phone: 'xx-999'
      addressLine1: 'somewhere'
      addressLine2: 'more spesific'
      city: 'Jaren'
      zip: 'N-2770'
      region: 'Oppland'
      country: 'Norway'

  incrCap: (i)->
    type: 'incr-member-cap'
    increment: i

  pushM : (x) ->
    if _.isArray x
      type: 'push-members'
      members: x
    else if _.isNumber x
      type: 'push-members'
      members: fix.members[0...x]
    else
      throw new Error 'fixture says hmmf!'

  popM : (x) ->
    type: 'pop-members'
    members: fix.members[0...x]