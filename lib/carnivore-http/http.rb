require 'reel'
require 'carnivore/source'

module Carnivore
  class Source

    class Http < Source

      attr_reader :args

      def setup(args={})
        @args = default_args(args)
      end

      def default_args(args)
        {
          :bind => '0.0.0.0',
          :port => '3000',
          :auto_respond => true
        }.merge(args)
      end

      # Transmit can be one of two things:
      # 1. Response back to an open connection
      # 2. Request to a remote source
      def transmit(message, *extra)
        options = extra.detect{|x| x.is_a?(Hash)} || {}
        orig = extra.detect{|x| x.is_a?(Carnivore::Message)}
        con = options[:connection]
        if(orig && con.nil?)
          con = orig[:message][:connection]
        end
        if(con) # response
          payload = message.is_a?(String) ? message : MultiJson.dump(message)
          # TODO: add `options` options for marshaling: json/xml/etc
          debug "Transmit response type with payload: #{payload}"
          con.respond(options[:code] || :ok, payload)
        else # request
          url = File.join("http://#{args[:bind]}:#{args[:port]}", options[:path].to_s)
          method = (options[:method] || :post).to_sym
          if(options[:headers])
            base = HTTP.with_headers(options[:headers])
          else
            base = HTTP
          end
          payload = message.is_a?(String) ? message : MultiJson.dump(message)
          debug "Transmit request type with payload: #{payload}"
          base.send(method, url, :body => payload)
        end
      end

      def confirm(message, args={})
        message[:message][:connection].respond(
          args[:code] || :ok, args[:response_body]
        )
      end

      def process(*process_args)
        srv = Reel::Server.supervise(args[:bind], args[:port]) do |con|
          while(req = con.request)
            begin
              msg = format(:request => req, :body => req.body.to_s, :connection => con)
              callbacks.each do |name|
                c_name = callback_name(name)
                debug "Dispatching #{msg} to callback<#{name} (#{c_name})>"
                Celluloid::Actor[c_name].async.call(msg)
              end
              con.respond(:ok, 'So long, and thanks for all the fish!') if args[:auto_respond]
            rescue => e
              con.respond(:bad_request, 'Failed to process request')
            end
          end
        end
      end

    end

  end
end
