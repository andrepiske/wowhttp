# frozen_string_literal: true
class TheHandler < Appmaker::Handler::Base
  def handle_request
    yt_match = @request.path.match %r(\A/yt/(.*)\.mp4\z)
    if yt_match != nil
      file_name = yt_match[1]
      unless File.exists? "public/yt/#{file_name}.mp4"
        puts "Downloading video #{file_name}..."
        `youtube-dl -o 'public/yt/%(id)s.mp4' 'https://www.youtube.com/watch?v=#{file_name}'`
        puts "Finish downloading!"
      end
    end

    sf = Appmaker::Handler::StaticFile.new @http_connection, @request
    respond_with_generic_not_found unless sf.handle_request
  end
end

srv = Appmaker::Net::Server.new '0.0.0.0', 3999
srv.start_listening TheHandler
srv.run_forever
