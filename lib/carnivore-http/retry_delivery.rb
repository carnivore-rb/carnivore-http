require 'carnivore-http'

module Carnivore
  module Http

    class RetryDelivery

      include Celluloid
      include Carnivore::Utils::Logging

      # @return [String] message directory
      attr_reader :message_directory

      # Create new instance
      #
      # @param directory [String] path to messages
      # @return [self]
      def initialize(directory)
        @message_directory = directory
        every(60){ attempt_redelivery }
      end

      # Attempt to deliver messages found in message directory
      #
      # @return [TrueClass, FalseClass] attempt was made
      # @note will not attempt if attempt is currently in progress
      def attempt_redelivery(message_id = '*')
        attempt = false
        begin
          unless(@delivering)
            @delivering = true
            attempt = true
            Dir.glob(File.join(message_directory, "#{message_id}.json")).each do |file|
              debug "Redelivery processing: #{file}"
              begin
                args = MultiJson.load(File.read(file)).to_smash
                debug "Restored from file #{file}: #{args.inspect}"
                if(redeliver(args[:message_id], args[:payload], args[:method], args[:url], args[:headers]))
                  FileUtils.rm(file)
                end
              rescue => e
                error "Failed to process file (#{file}): #{e.class}: #{e}"
                debug "#{e.class}: #{e}\n#{e.backtrace.join("\n")}"
              end
            end
          end
        rescue => e
          error "Unexpected error encountered during message redelivery! #{e.class}: #{e}"
          debug "#{e.class}: #{e}\n#{e.backtrace.join("\n")}"
        ensure
          @delivering = false
        end
        attempt
      end

      # Attempt redelivery of message
      #
      # @param message [Carnivore::Message]
      # @param payload [String] serialized payload
      # @param method [Symbol] HTTP method (:get, :post, etc)
      # @param url [String] endpoint URL
      # @param headers [Hash] request headers
      # @return [TrueClass, FalseClass] redelivery was successful
      def redeliver(message_id, payload, method, url, headers)
        begin
          base = headers.empty? ? HTTP : HTTP.with_headers(headers)
          uri = URI.parse(url)
          if(uri.userinfo)
            base = base.basic_auth(:user => uri.user, :pass => uri.password)
          end
          result = base.send(method, url, :body => payload)
          if(result.code < 200 || result.code > 299)
            error "Invalid response code received for #{message_id}: #{result.code} - #{result.reason}"
            false
          else
            info "Successful delivery of message on retry! Message ID: #{message_id}"
            true
          end
        rescue => e
          error "Transmission redelivery failure (Message ID: #{message_id}) - #{e.class}: #{e}"
          debug "#{e.class}: #{e}\n#{e.backtrace.join("\n")}"
          false
        end
      end

    end
  end
end
