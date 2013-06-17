express = require 'express'
redis = require 'redis'
crypto = require('crypto');

app = express()

if process.env.REDISTOGO_URL
  rtg   = require('url').parse process.env.REDISTOGO_URL
  redis = require('redis').createClient rtg.port, rtg.hostname
  redis.auth rtg.auth.split(':')[1] 
# Localhost
else
  redis = require("redis").createClient()

app.configure ->
  app.set 'port', process.env.PORT or 4000
  app.use express.bodyParser()
  app.use express.methodOverride()
  app.use express.cookieParser()


# key = The key by which to index the dictionary
Array::toDict = (key) ->
  @reduce ((dict, obj) -> dict[ obj[key] ] = obj if obj[key]?; return dict), {}


app.get '/lucky', (req, res) ->
	redis.get 'hashes', (status, hashes) ->
		hashes = JSON.parse hashes
		rand = Math.floor(Math.random() * hashes.length)
		key = hashes[rand]
		redis.get key, (status, data) ->
			res.send(data)

app.get '/all', (req, res) ->
	redis.get 'data', (status, data) ->
		res.send(data)


# App Routes
app.get '/', (request, response) ->
	response.send 'Hello, Quizlet'

app.get '/fetch_gdata', (_req, _res) ->
	key = process.env.GOOGLE_SPREADSHEET_KEY
	u   = "http://spreadsheets.google.com/feeds/list/#{key}/od6/public/basic?alt=json"
	f   = "spreadsheet_data.json"
	console.log "downloading #{u}"
	h = require('url').parse(u)
	(require('http').request h, (res) ->
	  console.log "res #{res.statusCode}"
	  res.setEncoding 'utf8'
	  data = ''
	  res.on 'error', (err) -> throw err
	  res.on 'data', (d) -> data += d
	  res.on 'end', () ->
	  	data = JSON.parse data
	  	data = data.feed.entry
	  	data = ({"hash":crypto.createHash('md5').update(item.title.$t).digest('hex'), "q":item.title.$t, "a":item.content.$t} for item in data)
	  	(redis.set item.hash, JSON.stringify {"q":item.q,"a":item.a} for item in data)
	  	hashes = (item.hash for item in data)
	  	(redis.set 'hashes', JSON.stringify hashes)
	  	dataDict = data.toDict('hash')
	  	redis.set 'data', data, (status) ->
	  		console.log "  updated #{f} (#{data.length} bytes) with status " + status
	  		_res.send data
	).end()


app.listen app.get('port'), () ->
  console.log "listening on port #{app.get('port')}"
