# frozen_string_literal: true
module Appmaker
  module Net
    module H2::Handlers::SettingsFrame
      def handle_h2_settings_frame fr
        if fr.payload_length % 6 != 0
          Debug.info "Invalid payload length: #{fr.payload_length}, terminating"
          return terminate_connection :FRAME_SIZE_ERROR
        end

        if fr.stream_identifier != 0
          Debug.info "Got SETTINGS for invalid stream (#{fr.stream_identifier}), terminating"
          return terminate_connection :PROTOCOL_ERROR
        end

        is_ack = ((fr.flags & 1) == 1)
        if is_ack
          Debug.info "Client ACK-ed our SETTINGS frame"

          terminate_connection :FRAME_SIZE_ERROR if fr.payload_length != 0

          return
        end

        new_settings = {}

        Debug.info("Got settings from client")
        num_params = fr.payload_length / 6
        (0...num_params).each do |idx|
          offset = idx * 6
          id = fr.payload[offset...offset+2].pack('C*').unpack('S>')[0]
          value = fr.payload[offset+2...offset+6].pack('C*').unpack('I>')[0]
          new_settings[h2_settingtype_to_sym(id)] = value

          if Debug.info?
            Debug.info("\tSet #{h2_settingtype_to_sym(id)} to #{value}")
          end
        end

        unless [nil, 0, 1].include?(new_settings[:SETTINGS_ENABLE_PUSH])
          Debug.info "Client sent invalid SETTINGS_ENABLE_PUSH (#{new_settings[:SETTINGS_ENABLE_PUSH]}), terminating"
          return terminate_connection :PROTOCOL_ERROR
        end

        if new_settings.has_key?(:SETTINGS_MAX_FRAME_SIZE)
          value = new_settings[:SETTINGS_INITIAL_WINDOW_SIZE]

          unless (16_384..2_147_483_647) === value
            Debug.info "Initial settings window size is out of bounds, terminating"
            return terminate_connection :FLOW_CONTROL_ERROR
          end
        end

        Debug.info("Got some settings, sending ACK") if Debug.info?

        if new_settings.has_key?(:SETTINGS_INITIAL_WINDOW_SIZE)
          new_value = new_settings[:SETTINGS_INITIAL_WINDOW_SIZE]

          if new_value > 2147483647
            Debug.info("Got invalid value for SETTINGS_INITIAL_WINDOW_SIZE (#{new_value}), terminating")
            return terminate_connection :FLOW_CONTROL_ERROR
          end

          if @settings[:SETTINGS_INITIAL_WINDOW_SIZE] != new_settings[:SETTINGS_INITIAL_WINDOW_SIZE]
          # TODO: move this somewhere else

            delta = new_value - @settings[:SETTINGS_INITIAL_WINDOW_SIZE]
            @h2streams.values.each do |stream|
              stream.change_window_size_by delta

              if stream.window_size > 2147483647
                Debug.info("Window size grew too large because initial window size changed, terminating")
                return terminate_connection :FLOW_CONTROL_ERROR
              end
            end
            Debug.info("Initial window size changed by #{delta}")
          end
        end

        new_settings.each do |key, value|
          @settings[key] = value
        end

        ack_frame = H2::Frame.new(:SETTINGS, 1, 0, 0, '', false)
        send_frame ack_frame
      end

      def h2_settingtype_to_sym id
        {
          0x01 => :SETTINGS_HEADER_TABLE_SIZE,
          0x02 => :SETTINGS_ENABLE_PUSH,
          0x03 => :SETTINGS_MAX_CONCURRENT_STREAMS,
          0x04 => :SETTINGS_INITIAL_WINDOW_SIZE,
          0x05 => :SETTINGS_MAX_FRAME_SIZE,
          0x06 => :SETTINGS_MAX_HEADER_LIST_SIZE,
        }[id]
      end
    end
  end
end
