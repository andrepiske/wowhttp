# frozen_string_literal: true
require 'mustermann'
require 'erubi'
require 'openssl'

class TheHandler < Appmaker::Handler::Base
  def handle_request
    routes = [
      { match: Mustermann.new('/'), proc_name: 'serve_master' },
      { match: Mustermann.new('/poll/:ammount'), proc_name: 'serve_poll' },
      { match: Mustermann.new('/not_found'), proc_name: 'serve_not_found' },
    ]

    routes.each do |route|
      match = route[:match].params(@request.path)
      if match
        method_name = route[:proc_name]
        @match = match
        send method_name
        return true
      end
    end

    sf = Appmaker::Handler::StaticFile.new @http_connection, @request
    return true if sf.handle_request

    make_a_redirect
    true
  end

  def serve_master
    resp = make_base_response
    resp.code = 200

    current_time = Time.now.to_s
    src = Erubi::Engine.new(File.read("views/index.erb")).src

    content = eval(src)

    respond_with_content resp, content, 'text/html'
  end

  def make_a_redirect
    resp = make_base_response
    resp.code = 303
    resp.set_header 'Location', '/not_found'
    respond_with_content resp, '<strong>404 - Not found</strong>', 'text/html'
  end

  def serve_not_found
    resp = make_base_response
    resp.code = 404
    respond_with_content resp, '<strong>404 - Not found</strong>', 'text/html'
  end

  def serve_poll
    Thread.start do
      Thread.current.report_on_exception = true
      do_not_keepalive!

      response = make_base_response
      response.code = 200
      response.set_header 'Content-Type', 'text/event-stream'
      response.set_header 'Transfer-Encoding', 'chunked'

      conn = @http_connection

      am = @match['ammount'].to_i
      chunks = [
        [ 10, 15 ].pack('C*'),
        [ 21, 22, 23 ].pack('C*'),
        [ 33, 38, 39 ].pack('C*'),
        [ 40, 41, 42 ].pack('C*'),
        [ 50 ].pack('C*'),
        [ 60, 66, 67, 68 ].pack('C*'),
        # 'hello',
        # 'world',
        # 'how',
        # 'are',
        # 'you?',
      ].take(am)

      conn.write response.full_header

      chunks.each do |ck|
        len = ck.length.to_s 0x10
        data = "#{len};Content-Type=\"text/plain; encoding=ascii\"\r\n#{ck}\r\n"
        conn.write data
        sleep(0.4)
      end

      conn.write_then_finish "0\r\n\r\n"
    end
  end
end

Process.setproctitle('appmaker')

def configure_ssl(srv)
  base_path = File.expand_path("#{__FILE__}/../keys/intermediate")
  cert_store = OpenSSL::X509::Store.new

  cert_path = "#{base_path}/certs/www.hadronltd.com.multi.cert.pem"
  key_path = "#{base_path}/private/www.hadronltd.com.key.pem"
  ca_chain_path = "#{base_path}/certs/ca-chain.cert.pem"

  password = File.read('./ssl_key_password').chomp
  puts("cert path = '#{cert_path}' with pass='#{password}'")

  key = OpenSSL::PKey::RSA.new(File.read(key_path), password)
  cert = OpenSSL::X509::Certificate.new(File.read(cert_path))

  cert_store.add_cert(cert)
  cert_store.add_cert(OpenSSL::X509::Certificate.new(File.read(ca_chain_path)))

  srv.configure_ssl(cert, key, cert_store)
end

def setup_server
  srv = Appmaker::Net::Server.new '0.0.0.0', 3999
  configure_ssl(srv)
  srv.start_listening TheHandler
  srv
end
setup_server.run_forever
