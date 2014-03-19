Promise = require 'bluebird'
_ = require 'lodash'
fs = Promise.promisifyAll require 'fs'
url = require 'url'
knex = require './db'
crypto = require 'crypto'
csrgen = Promise.promisify require 'csr-gen'
request = Promise.promisify require 'request'

module.exports = (uuid) ->
	# Load config file
	config = fs.readFileAsync('/boot/config.json', 'utf8').then(JSON.parse)

	# Generate SSL certificate
	keys = csrgen(uuid,
		company: 'Rulemotion Ltd'
		csrName: 'client.csr'
		keyName: 'client.key'
		outputDir: '/supervisor/data'
		email: 'vpn@resin.io'
		read: true
		country: ''
		city: ''
		state: ''
		division: ''
	)

	Promise.all([config, keys])
	.then ([config, keys]) ->
		console.log('UUID:', uuid)
		console.log('User ID:', config.userId)
		console.log('User:', config.username)
		console.log('API key:', config.apiKey)
		console.log('Application ID:', config.applicationId)
		console.log('CSR :', keys.csr)
		console.log('Posting to the API..')
		config.csr = keys.csr
		config.uuid = uuid
		return request(
			method: 'POST'
			url: url.resolve(process.env.API_ENDPOINT, 'associate')
			json: config
		)
	.spread (response, body) ->
		if response.statusCode >= 400
			throw body

		console.log('Configuring VPN..')
		vpnConf = fs.readFileAsync('/supervisor/src/openvpn.conf.tmpl', 'utf8')
			.then (tmpl) ->
				fs.writeFileAsync('/supervisor/data/client.conf', _.template(tmpl)(body))

		Promise.all([
			fs.writeFileAsync('/supervisor/data/ca.crt', body.ca)
			fs.writeFileAsync('/supervisor/data/client.crt', body.cert)
			vpnConf
		])
	.then ->
		console.log('Finishing bootstrapping')
		Promise.all([
			knex('config').truncate()
			.then ->
				config
				.then (config) ->
					knex('config').insert([
						{key: 'uuid', value: uuid}
						{key: 'apiKey', value: config.apiKey}
						{key: 'username', value: config.username}
						{key: 'userId', value: config.userId}
					])
			knex('app').truncate()
		])
	.catch (error) ->
		console.log(error)
