require 'xmlrpc/client'
require 'msgpack'

require 'rex'
require 'rex/proto/http'

require 'msf/core/rpc/v10/constants'

module Msf
module RPC

class Client

	attr_accessor :sock, :token, :info


	def initialize(info={})
		self.info = {
			:host => '127.0.0.1',
			:port => 3790,
			:uri  => '/api/',
			:ssl  => true,
			:ssl_version => 'SSLv3',
			:context     => {}
		}.merge(info)

		self.token = self.info[:token]
	end


	def login(user,pass)
		res = self.call("auth.login", user, pass)
		if(not (res and res['result'] == "success"))
			raise RuntimeError, "authentication failed"
		end
		self.token = res['token']
		true
	end

	# Prepend the authentication token as the first parameter
	# of every call except auth.login. Requires the
	def call(meth, *args)
		if(meth != "auth.login")
			if(not self.token)
				raise RuntimeError, "client not authenticated"
			end
			args.unshift(self.token)
		end

		args.unshift(meth)

		if not @cli
			@cli = Rex::Proto::Http::Client.new(info[:host], info[:port], info[:context], info[:ssl], info[:ssl_version])
			@cli.set_config(
				:vhost => info[:host],
				:agent => "Metasploit RPC Client/#{API_VERSION}",
				:read_max_data => (1024*1024*512)
			)
		end

		req = @cli.request_cgi(
			'method' => 'POST',
			'uri'    => self.info[:uri],
			'ctype'  => 'binary/message-pack',
			'data'   => args.to_msgpack
		)

		res = @cli.send_recv(req)

		if res and [200, 401, 403, 500].include?(res.code)
			resp = MessagePack.unpack(res.body)

			if resp and resp.kind_of?(::Hash) and resp['error'] == true
				raise Msf::RPC::ServerException.new(res.code, resp['error_message'] || resp['error_string'], resp['error_class'], resp['error_backtrace'])
			end

			return resp
		else
			raise RuntimeError, res.inspect
		end
	end

	def close
		self.sock.close rescue nil
		self.sock = nil
	end

end
end
end

