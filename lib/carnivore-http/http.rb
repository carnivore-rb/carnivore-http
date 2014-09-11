require 'reel'
require 'tempfile'
require 'carnivore/source'
require 'carnivore-http/utils'

module Carnivore
  class Source

    # Carnivore HTTP source
    class Http < Source

      trap_exit :retry_delivery_failure

      include Carnivore::Http::Utils::Params

      # @return [Hash] source arguments
      attr_reader :args
      # @return [Carnivore::Http::RetryDelivery]
      attr_reader :retry_delivery

      # Setup the source
      #
      # @params args [Hash] setup arguments
      def setup(args={})
        require 'fileutils'
        @args = default_args(args)
        if(retry_directory)
          info "Delivery retry has been enabled for this source (#{name})"
          @retry_delivery = Carnivore::Http::RetryDelivery.new(retry_directory)
          self.link retry_delivery
        end
      end

      # Handle failed retry deliveries
      #
      # @param actor [Object] terminated actor
      # @param reason [Exception] reason for termination
      # @return [NilClass]
      def retry_delivery_failure(actor, reason)
        if(actor == retry_delivery)
          error "Failed RetryDelivery encountered: #{reason}. Rebuilding."
          @retry_delivery = Carnivore::Http::RetryDelivery.new(retry_directory)
        else
          error "Unknown actor failure encountered: #{reason}"
        end
        nil
      end

      # @return [String, NilClass] directory storing failed messages
      def retry_directory
        if(args[:retry_directory])
          FileUtils.mkdir_p(File.join(args[:retry_directory], name.to_s)).first
        end
      end

      # @return [String, NilClass] cache directory for initial writes
      def retry_write_directory
        base = retry_directory
        if(base)
          FileUtils.mkdir_p(File.join(base, '.write')).first
        end
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
          :auto_respond => true,
          :retry_directory => '/tmp/.carnivore-resend'
        ).merge(args)
      end

      # Always auto start
      def auto_process?
        true
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
          code = options.fetch(:code, :ok)
          info "Transmit response type for #{message} with code: #{code}"
          con.respond(code, payload)
        else # request
          if(args[:endpoint])
            url = args[:endpoint]
          else
            url = "http#{'s' if args[:ssl]}://#{args[:bind]}"
            if(args[:port])
              url << ":#{args[:port]}"
            end
            url = URI.join(url, args.fetch(:path, '/')).to_s
          end
          if(options[:path])
            url = URI.join(url, options[:path].to_s)
          end
          method = options.fetch(:method,
            args.fetch(:method, :post)
          ).to_s.downcase.to_sym
          payload = message.is_a?(String) ? message : MultiJson.dump(message)
          info "Transmit request type for message #{message}"
          perform_transmission(message, payload, method, url, options.fetch(:headers, {}))
        end
      end

      # Transmit message to HTTP endpoint
      #
      # @param message [Carnivore::Message]
      # @param payload [String] serialized payload
      # @param method [Symbol] HTTP method (:get, :post, etc)
      # @param url [String] endpoint URL
      # @param headers [Hash] request headers
      # @return [HTTP::Response]
      def perform_transmission(message, payload, method, url, headers={})
        begin
          base = headers.empty? ? HTTP : HTTP.with_headers(headers)
          uri = URI.parse(url)
          if(uri.userinfo)
            base = base.basic_auth(:user => uri.user, :pass => uri.password)
          end
          result = base.send(method, url, :body => payload)
          if(result.code < 200 || result.code > 299)
            error "Invalid response code received for #{message}: #{result.code} - #{result.reason}"
            write_for_retry(message.object_id, payload, method, url, headers)
          end
        rescue => e
          error "Transmission failure (#{message}) - #{e.class}: #{e}"
          debug "#{e.class}: #{e}\n#{e.backtrace.join("\n")}"
          write_for_retry(message.object_id, payload, method, url, headers)
        end
      end

      # Persist message if enabled for send retry
      #
      # @param message_id [String] ID of originating message
      # @param payload [String] serialized payload
      # @param method [Symbol] HTTP method (:get, :post, etc)
      # @param url [String] endpoint URL
      # @param headers [Hash] request headers
      # @return [TrueClass, FalseClass] message persisted
      def write_for_retry(message_id, payload, method, url, headers)
        data = {
          :message_id => message_id,
          :payload => payload,
          :method => method,
          :url => url,
          :headers => headers
        }
        if(retry_directory)
          stage_path = File.join(rewrite_retry_directory, "#{Celluloid.uuid}.json")
          final_path = File.join(retry_directory, File.dirname(stage_path))
          File.open(stage_path, 'w+') do |file|
            file.write MultiJson.dump(data)
          end
          FileUtils.move(stage_path, final_path)
          info "Failed message (ID: #{message_id}) persisted for resend"
          true
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
        unless(@processing)
          @processing = true
          srv = Reel::Server::HTTP.supervise(args[:bind], args[:port]) do |con|
            con.each_request do |req|
              begin
                msg = build_message(con, req)
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
          true
        else
          false
        end
      end

      # Size limit for inline body
      BODY_TO_FILE_SIZE = 1024 * 10 # 10K

      # Build message hash from request
      #
      # @param con [Reel::Connection]
      # @param req [Reel::Request]
      # @return [Hash]
      # @note
      #   if body size is greater than BODY_TO_FILE_SIZE
      #   the body will be a temp file instead of a string
      def build_message(con, req)
        msg = Smash.new(
          :request => req,
          :headers => Smash[
            req.headers.map{ |k,v| [k.downcase.tr('-', '_'), v]}
          ],
          :connection => con,
          :query => parse_query_string(req.query_string)
        )
        if(msg[:headers][:content_type] == 'application/json')
          msg[:body] = MultiJson.load(
            req.body.to_s
          )
        elsif(msg[:headers][:content_type] == 'application/x-www-form-urlencoded')
          msg[:body] = parse_query_string(
            req.body.to_s
          )
          if(msg[:body].size == 1 && msg[:body].values.first.is_a?(Array) && msg[:body].values.first.empty?)
            msg[:body] = msg[:body].keys.first
          end
        elsif(msg[:headers][:content_length].to_i > BODY_TO_FILE_SIZE)
          msg[:body] = Tempfile.new('carnivore-http')
          while((chunk = req.body.readpartial(2048)))
            msg[:body] << chunk
          end
          msg[:body].rewind
        else
          msg[:body] = req.body.to_s
        end
        format(msg)
      end

    end

  end
end
