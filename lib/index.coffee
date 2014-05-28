app = module.exports = require('derby').createApp 'ctf', __filename
app.loadViews __dirname
app.loadStyles __dirname
app.component require('d-connection-alert')
app.component require('d-before-unload')

TEAMS = ['red', 'green']
ROLES = TEAMS.concat 'admin', 'neutral'
ONE_DAY = 1000 * 60 * 60 * 24

app.on 'model', (model) ->
  # Defined by name so that it can be re-initialized on the client
  model.fn 'pluckUserIds', (items = {}, additional) ->
    ids = {}
    ids[additional] = true if additional
    for key, item of items
      ids[item.userId] = true if item?.userId
    return Object.keys ids

app.get '/:room?', (page, model, {room}, next) ->
  # matches are alphanumeric-underscore-dash
  return page.redirect '/match/' + (room || 'lobby')

app.get '/match/:room?', (page, model, {room}, next) ->
  # matches are alphanumeric-underscore-dash
  unless room && /^[a-zA-Z0-9_-]+$/.test room
    return page.redirect '/match/lobby'
  model.set '_page.roles', ROLES
  model.set '_page.room', room

  roomQuery = model.at 'rooms.' + room
  roomQuery.subscribe (err) ->
    return next err if err

    messagesQuery = model.query 'messages',
      room: room
      # time: {$gt: new Date - ONE_DAY}

    messagesQuery.subscribe (err) ->
      return next err if err

      # Subscribe to all displayed userIds, including the userIds associated
      # with each message and the current session's userId
      model.start '_page.userIds', 'messages', '_session.userId', 'pluckUserIds'
      usersQuery = model.query 'users', '_page.userIds'
      usersQuery.subscribe (err) ->
        return next err if err

        user = model.at 'users.' + model.get('_session.userId')
        # Render page if the user already exists
        return page.render() if user.get()

        # Otherwise, initialize user and render
        userCount = model.at 'ctf.userCount'
        userCount.fetch (err) ->
          return next err if err
          userCount.increment (err) ->
            return next err if err
            user.set
              name: 'Runner ' + userCount.get()
              team: 'neutral'
              settings: true
            page.render()

# Called on both the server and the client before rendering
app.proto.init = (model) ->
  # Filters and sorts get computed in the client, so messages will appear
  # immediately even if the client is offline
  timeSort = (a, b) -> a?.time - b?.time
  model.sort('messages', timeSort).ref '_page.list'

# Called only on the browser after rendering
app.proto.create = (model) ->
  # Times are suppressed when server rendering, since we don't know the client's
  # timezone. More ideally, the user's timezone would be stored on the server
  # and passed to the formatTime function
  model.set '_page.showTime', true

  # Scroll to the bottom by default
  @atBottom = true
  # Scoll the page on message insertion or when a new message is loaded by the
  # subscription, which might happen after insertion
  model.on 'all', '_page.list', =>
    # Don't auto-scroll the page if the user has scrolled up from the bottom
    return unless @atBottom
    @container.scrollTop = @list.offsetHeight

app.proto.onScroll = ->
  # Update whether the user scrolled up from the bottom or not
  bottom = @list.offsetHeight
  containerHeight = @container.offsetHeight
  scrollBottom = @container.scrollTop + containerHeight
  @atBottom = bottom < containerHeight || scrollBottom > bottom - 100

app.proto.add = ->
  model = @model
  comment = model.del '_page.newComment'
  # Scroll the page regardless when posting
  @atBottom = true
  id = model.add 'messages',
    room: model.get '_page.room'
    userId: model.get '_session.userId'
    comment: comment
    time: +new Date
  if navigator.geolocation?
    navigator.geolocation.getCurrentPosition (geo) ->
      coords = {}
      for prop of geo.coords
        coords[prop] = geo.coords[prop]
      model.set 'messages.'+id+'.geo', coords

app.proto.formatTime = (message) ->
  time = message && message.time
  return unless time
  time = new Date time
  return [time.getHours(), time.getMinutes(), time.getSeconds()]
    .map (n) -> (if n < 10 then '0' else '') + n
    .join ':'

app.proto.formatGeo = (message) ->
  geo = message && message.geo
  return unless geo
  return geo.latitude+', '+geo.longitude
