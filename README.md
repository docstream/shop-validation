# shop-validation
clientside and serverside schemas for shop-events

Testing a new events/data-Block in the current CONTEXT aka snapshot

(snapshot is also validated)

    # throws an error
    #   error has .data = same as dataBlock , but annotated w error-info
     
    try
      validate {snapshot}, [ {dataBlock} ]
    catch err
      console.log err.message
      console.log err.data


TODO; browserify
