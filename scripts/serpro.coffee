typing = (res, t) ->
	res.robot.adapter.callMethod 'stream-notify-room', res.envelope.room+'/typing', res.robot.alias, t is true

livechatTransferHuman = (res) ->
	setTimeout ->
		res.robot.adapter.callMethod 'livechat:transfer',
			roomId: res.envelope.room
			departmentId: process.env.DEPARTMENT_ID
	, 1000

setUserName = (res, name) ->
	res.robot.adapter.callMethod 'livechat:saveInfo',
		_id: res.envelope.user.id
		name: name
	,
		_id: res.envelope.room

incErrors = (res) ->
	errors = res.robot.brain.get('errors_'+res.envelope.room) or 0
	errors++
	res.robot.brain.set('errors_'+res.envelope.room, errors)
	return errors

clearErrors = (res) ->
	res.robot.brain.set('errors_'+res.envelope.room, 0)

processErrors = (res, message) ->
	switch message
		when 'Desculpe mas não entendi, pode ser mais especifico?'
			errors = incErrors res
			switch errors
				when 1
					return 'Desculpa, não entendi bem o que você quis dizer, você pode ser mais especifico?'
				when 2
					return 'Ah, legal, eu não sei sobre isso não. Eu já estudei sobre o ProUni, sobre FIES, sei sobre conteúdos educacionais, sobre escolas e universidades. Pergunte sobre um desses temas ou se você preferir posso lhe passar para um atendente?'
				else
					return {
						message: 'Estou sentindo que não estou estou conseguindo te ajudar. Vou chamar meu supervisor, aguarde só um minutinho...'
						callback: ->
							livechatTransferHuman res
							clearErrors res
					}
		when 'pausar_bot'
			return {
				message: 'Ok, me de um minuto que estou adicionando um amigo humano nesta conversa...'
				callback: ->
					livechatTransferHuman res
			}
		else
			clearErrors res

	return message


processJson = (res, json) ->
	console.log 'json', json

processBodyJson = (body) ->
	lines = body.split '\n'

	if lines[0].indexOf('json:{') is 0
		parts = lines[0].split('-;-')
		if parts[1]
			lines[0] = parts[1]
		else
			lines = lines.splice(0, 1)

		try
			json = JSON.parse(parts[0].replace('json:', ''))
			processJson(res, json)
		catch e
			console.log 'Invalid JSON'

	return lines.join('\n')

replyWithNaturalDelay = (res, msg, elapsed=0) ->
	keysPerSecond = 50
	maxResponseTimeInSeconds = 3

	if typeof msg isnt 'string'
		cb = msg.callback
		msg = msg.message

	delay = Math.min(Math.max((msg.length / keysPerSecond) * 1000 - elapsed, 0), maxResponseTimeInSeconds * 1000)
	typing res, true
	setTimeout ->
		res.send msg
		typing res, false
		cb?()
	, delay

url = 'https://itsnow.com.br/chat/rocket'

module.exports = (robot) ->

	robot.hear /(.+)/i, (res) ->
		message = res.match[0].replace res.robot.name+' ', ''
		message = message.replace(/^\s+/, '')
		message = message.replace(/\s+&/, '')

		if robot.brain.get('user_without_name_'+res.envelope.room) is true
			if message.indexOf(' ') > -1
				replyWithNaturalDelay res, 'Vamos simplificar, me diga o seu primeiro nome apenas'
				return

			setUserName(res, message)
			res.envelope.user.alias = message
			message = robot.brain.get('last_message_'+res.envelope.room)
			robot.brain.set('user_without_name_'+res.envelope.room, false)

		robot.brain.set('last_message_'+res.envelope.room, message)

		if not res.envelope.user.alias
			robot.brain.set('user_without_name_'+res.envelope.room, true)
			replyWithNaturalDelay res, 'Então, para que possamos começar nossa conversa me diga seu nome'
			return

		typing res, true
		start = Date.now()

		data =
			cod: process.env.ITSNOW_CODE
			nome: res.envelope.user.alias
			email: res.envelope.user.name+'@rocket.chat'
			mensagem: message

		robot.http(url)
			.header('Content-Type', 'application/json')
			.post(JSON.stringify(data)) (err, httpRes, body) ->
				console.log err, body

				if typeof body isnt 'string'
					return

				body = body.replace /\n+$/, ''

				body = processBodyJson body
				body = processErrors res, body

				end = Date.now()
				diff = end - start

				replyWithNaturalDelay res, body, diff
