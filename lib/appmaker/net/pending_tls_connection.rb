# frozen_string_literal: true

class Appmaker::Net::PendingTlsConnection
  attr_reader :socket, :monitor, :server

  def initialize server, monitor, socket
    @monitor = monitor
    @server = server
    @socket = socket
    @tries = 0
  end

  def notify_writeable
    accept_connection
  end

  def notify_readable
    accept_connection
  end

  def dump_diagnosis_info
  end

  def mon_write_buffer_length
    0
  end

  def mon_write_buffer_chunks
    0
  end

  def go!
  end

  private

  def accept_connection
    begin
      ssl_result = @socket.accept_nonblock(exception: false)
    rescue OpenSSL::OpenSSLError => e
      # raise SSLError,
      Appmaker::Debug.warn "OpenSSLError: #{e.class} message=#{e.message}"
    end

    if ssl_result == :wait_readable || ssl_result == :wait_writable
      @tries += 1
      return
    end

    @server.accepted_pending_tls_connection(self, ssl_result)
  end
end
