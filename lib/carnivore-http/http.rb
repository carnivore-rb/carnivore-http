require 'reel'
require 'tempfile'
require 'carnivore/source'
require 'carnivore-http/utils'

module Carnivore
  class Source

    # Carnivore HTTP source
    class Http < Source

      include Carnivore::Http::Utils::Params

      # @return [Hash] source arguments
      attr_reader :args

      # Setup the source
      #
      # @params args [Hash] setup arguments
      def setup(args={})
        @args = default_args(args)
      end

      # Default configuration arguments. If hash is provided, it
      # will be merged into the default arguments.
      #
      # @param args [Hash]
      # @return [Hash]
      def default_args(args={})
        Smash.new(
          :bind => '0.0.0.0',
          :port => '3000',
          :auto_respond => true
        ).merge(args)
      end

      # Tranmit message. The transmission can be a response
      # back to an open connection, or a request to a remote
      # source (remote carnivore-http source generally)
      #
      # @param message [Object] message to transmit
      # @param extras [Object] argument list
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

      # Confirm processing of message
      #
      # @param message [Carnivore::Message]
      # @param args [Hash]
      # @option args [Symbol] :code return code
      def confirm(message, args={})
        code = args.delete(:code) || :ok
        args[:response_body] = 'Thanks' if code == :ok && args.empty?
        debug "Confirming #{message} with: Code: #{code.inspect} Args: #{args.inspect}"
        message[:message][:request].respond(code, args[:response_body] || args)
      end

      # Process requests
      def process(*process_args)
        srv = Reel::Server::HTTP.supervise(args[:bind], args[:port]) do |con|
          con.each_request do |req|
            begin
              msg = build_message(req)
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

      # Size limit for inline body
      BODY_TO_FILE_SIZE = 1024 * 10 # 10K

      # Build message hash from request
      #
      # @param req [Reel::Request]
      # @return [Hash]
      # @note
      #   if body size is greater than BODY_TO_FILE_SIZE
      #   the body will be a temp file instead of a string
      def build_message(req)
        msg = format(
          :request => req,
          :headers => req.headers,
          :connection => con,
          :query => parse_query_string(req.query_string)
        )
        if(req.headers['Content-Type'] == 'application/json')
          msg[:query].merge(
            parase_query_string(
              req.body.to_s
            )
          )
          msg[:body] = req.body.to_s
        elsif(req.headers['Content-Length'].to_i > BODY_TO_FILE_SIZE)
          msg[:body] = Tempfile.new('carnivore-http')
          while((chunk = req.body.readpartial(2048)))
            msg[:body] << chunk
          end
          msg[:body].rewind
        else
          msg[:body] = req.body.to_s
        end
        msg
      end

    end

  end
end
