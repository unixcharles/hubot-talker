{Adapter,Robot,TextMessage,EnterMessage,LeaveMessage} = require 'hubot'

HTTPS        = require 'https'
EventEmitter = require('events').EventEmitter
net          = require('net')
tls          = require('tls')

class Talker extends Adapter
  send: (user, strings...) ->
    strings.forEach (str) =>
      @bot.write user.room, {"type": "message", "content": str}

  reply: (user, strings...) ->
    strings.forEach (str) =>
      @send user, "@#{user.name} #{str}"

  run: ->
    self = @
    token = process.env.HUBOT_TALKER_TOKEN
    rooms = process.env.HUBOT_TALKER_ROOMS.split(',')

    bot = new TalkerClient()
    console.log bot

    ping = (room)->
      setInterval ->
        bot.write room, {type: "ping"}
      , 25000

    bot.on "Ready", (room)->
      message = {"room": room, "token": token, "type": "connect"}
      bot.write room, message
      ping room

    bot.on "Users", (message)->
      for user in message.users
        self.userForId(user.id, user)

    bot.on "TextMessage", (room, message)->
      unless self.robot.name == message.user.name
        # Replace "@mention" with "mention: ", case-insensitively
        name_escape_regexp = new RegExp("[.*+?|()\\[\\]{}\\\\]", "g")
        escaped_name = self.robot.name.replace( name_escape_regexp, "\\$&")

        name_regexp = new RegExp "^@#{escaped_name}", 'i'
        content = message.content.replace(name_regexp, self.robot.name)

        self.receive new TextMessage self.userForMessage(room, message), content

    bot.on "EnterMessage", (room, message) ->
      unless self.robot.name == message.user.name
        self.receive new EnterMessage self.userForMessage(room, message)

    bot.on "LeaveMessage", (room, message) ->
      unless self.robot.name == message.user.name
        self.receive new LeaveMessage self.userForMessage(room, message)

    for room in rooms
      bot.sockets[room] = bot.createSocket(room)

    @bot = bot

    self.emit "connected"

  userForMessage: (room, message)->
    author = @userForId(message.user.id, message.user)
    author.room = room
    author

exports.use = (robot) ->
  new Talker robot

class TalkerClient extends EventEmitter
  constructor: ->
    @host          = 'talkerapp.com'
    @encoding      = 'utf8'
    @port          = 8500
    @sockets       = {}

  createSocket: (room) ->
    self = @

    socket = tls.connect @port, @host, ->
      console.log("Connected to room #{room}.")
      self.emit "Ready", room

    #callback
    socket.on 'data', (data) ->
      for line in data.split '\n'
        message = if line is '' then null else JSON.parse(line)

        if message
          console.log "From room #{room}: #{line}"
          if message.type == "users"
            self.emit "Users", message
          if message.type == "message"
            self.emit "TextMessage", room, message
          if message.type == "join"
            self.emit "EnterMessage", room, message
          if message.type == "leave"
            self.emit "LeaveMessage", room, message
          if message.type == "error"
            self.disconnect room, message.message

    socket.addListener "eof", ->
      console.log "eof"
    socket.addListener "timeout", ->
      console.log "timeout"
    socket.addListener "end", ->
      console.log "end"

    socket.setEncoding @encoding

    socket

  write: (room, args) ->
    self = @
    @sockets[room]

    if @sockets[room].readyState != 'open'
      return @disconnect 'cannot send with readyState: ' + @sockets[room].readyState

    message = JSON.stringify(args)
    console.log "To room #{room}: #{message}"

    @sockets[room].write message, @encoding

  disconnect: (room, why) ->
    if @sockets[room] != 'closed'
      @sockets[room]
      console.log 'disconnected (reason: ' + why + ')'
