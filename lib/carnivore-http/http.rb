require 'reel'
require 'carnivore/source'
require 'carnivore-http/utils'

module Carnivore
  class Source

    # Carnivore HTTP source
    class Http < Source

      include Carnivore::Http::Utils::Params

      attr_reader :args

      def setup(args={})
        @args = default_args(args)
      end

      def default_args(args)
        Smash.new(
          :bind => '0.0.0.0',
          :port => '3000',
          :auto_respond => true
        ).merge(args)
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
        code = args.delete(:code) || :ok
        args[:response_body] = 'Thanks' if code == :ok && args.empty?
        debug "Confirming #{message} with: Code: #{code.inspect} Args: #{args.inspect}"
        message[:message][:request].respond(code, args[:response_body] || args)
      end

      def process(*process_args)
        srv = Reel::Server::HTTP.supervise(args[:bind], args[:port]) do |con|
          con.each_request do |req|
            begin
              msg = format(
                :request => req,
                :headers => req.headers,
                :body => req.body.to_s,
                :connection => con,
                :query => parse_query_string(req.query_string).merge(parse_query_string(req.body.to_s))
              )
              callbacks.each do |name|
                c_name = callback_name(name)
                debug "Dispatching #{msg} to callback<#{name} (#{c_name})>"
                callback_supervisor[c_name].call(msg)
              end
              req.respond(:ok, 'So long, and thanks for all the fish!') if args[:auto_respond]
            rescue => e
              req.respond(:bad_request, "Failed to process request -> #{e}")
            end
          end
        end
      end

    end

  end
end
