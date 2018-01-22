#fixture
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

  acc : ->
    type: 'account'
    name: 'PER AS'
    phone: 'xx-999'
    billingAddress: 
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
    type: 'push-members'
    members: fix.members[0...x]

  popM : (x) ->
    type: 'pop-members'
    members: fix.members[0...x]