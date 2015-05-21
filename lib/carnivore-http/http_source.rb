require 'reel'
require 'tempfile'
require 'carnivore/source'
require 'carnivore-http/utils'

module Carnivore
  class Source

    # Carnivore HTTP source
    class HttpSource < Source

      trap_exit :retry_delivery_failure

      include Carnivore::Http::Utils::Params

      # @return [Hash] source arguments
      attr_reader :args
      # @return [Carnivore::Http::RetryDelivery]
      attr_reader :retry_delivery
      # @return [Array<IPAddr>] allowed request origin addresses
      attr_reader :auth_allowed_origins
      # @return [HTAuth::PasswdFile]
      attr_reader :auth_htpasswd

      # Setup the source
      #
      # @params args [Hash] setup arguments
      def setup(args={})
        require 'fileutils'
        @args = default_args(args)
        @retry_delivery = Carnivore::Http::RetryDelivery.new(retry_directory)
        self.link retry_delivery
        if(args.get(:authorization, :allowed_origins))
          require 'ipaddr'
          @allowed_origins = [args.get(:authorization, :allowed_origins)].flatten.compact.map do |origin_check|
            IPAddr.new(origin_check)
          end
        end
        if(args.get(:authorization, :htpasswd))
          require 'htauth'
          @auth_htpasswd = HTAuth::PasswdFile.open(
            args.get(:authorization, :htpasswd)
          )
        end
      end

      # Handle failed retry deliveries
      #
      # @param actor [Object] terminated actor
      # @param reason [Exception] reason for termination
      # @return [NilClass]
      def retry_delivery_failure(actor, reason)
        if(actor == retry_delivery)
          if(reason)
            error "Failed RetryDelivery encountered: #{reason}. Rebuilding."
            @retry_delivery = Carnivore::Http::RetryDelivery.new(retry_directory)
          else
            info 'Encountered RetryDelivery failure. No reason so assuming teardown.'
          end
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
        args.has_key?(:enable_processing) ? args[:enable_processing] : true
      end

      # Message is authorized for processing
      #
      # @param message [Carnivore::Message]
      # @return [TrueClass, FalseClass]
      # @note Authorization is driven via the source configuration.
      #   Valid structure looks like:
      #     {
      #       :type => 'http',
      #       :args => {
      #         :authorization => {
      #           :allowed_origins => ['127.0.0.1', '192.168.0.2', '192.168.6.0/24'],
      #           :htpasswd => '/path/to/htpasswd.file',
      #           :credentials => {
      #             :username1 => 'password1'
      #           },
      #           :valid_on => :all # or :any
      #         }
      #       }
      #     }
      #   When multiple authorization items are provided, the
      #   `:valid_on` will define behavior. It will default to `:all`.
      def authorized?(message)
        if(args.fetch(:authorization))
          valid_on = args.fetch(:authorization, :valid_on, :all).to_sym
          case valid_on
          when :all
            allowed_origin?(message) &&
              allowed_htpasswd?(message) &&
              allowed_credentials?(message)
          when :any
            allowed_origin?(message) ||
              allowed_htpasswd?(message) ||
              allowed_credentials?(message)
          when :none
            true
          else
            raise ArgumentError.new "Unknown authorization `:valid_on` provided! Given: #{valid_on}. Allowed: `any` or `all`"
          end
        else
          true
        end
      end

      # Check if message is allowed based on htpasswd file
      #
      # @param message [Carnivore::Message]
      # @return [TrueClass, FalseClass]
      def allowed_htpasswd?(message)
        if(auth_htpasswd)
          entry = auth_htpasswd.fetch(message[:message][:authentication][:username])
          if(entry)
            entry.authenticated?(message[:message][:authentication][:password])
          else
            false
          end
        else
          true
        end
      end

      # Check if message is allowed based on config credentials
      #
      # @param message [Carnivore::Message]
      # @return [TrueClass, FalseClass]
      def allowed_credentials?(message)
        if(creds = args.get(:authorization, :credentials))
          creds[message[:message][:authentication][:username]] == message[:message][:authentication][:password]
        else
          true
        end
      end

      # Check if message is allowed based on origin
      #
      # @param message [Carnivore::Message]
      # @return [TrueClass, FalseClass]
      def allowed_origin?(message)
        if(auth_allowed_origins)
          !!auth_allowed_origins.detect do |allowed_check|
            allowed_check.include?(message[:message][:origin])
          end
        else
          true
        end
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
          info "Transmit response type with code: #{code}"
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
          message_id = message.is_a?(Hash) ? message.fetch(:id, Celluloid.uuid) : Celluloid.uuid
          payload = message.is_a?(String) ? message : MultiJson.dump(message)
          info "Transmit request type for Message ID: #{message_id}"
          async.perform_transmission(message_id.to_s, payload, method, url, options.fetch(:headers, {}))
        end
      end

      # Transmit message to HTTP endpoint
      #
      # @param message_id [String]
      # @param payload [String] serialized payload
      # @param method [Symbol] HTTP method (:get, :post, etc)
      # @param url [String] endpoint URL
      # @param headers [Hash] request headers
      # @return [NilClass]
      def perform_transmission(message_id, payload, method, url, headers={})
        unless(retry_delivery.redeliver(message_id, payload, method, url, headers))
          write_for_retry(message_id, payload, method, url, headers)
          retry_delivery.async.attempt_redelivery(message_id)
        end
        nil
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
          stage_path = File.join(retry_write_directory, "#{message_id}.json")
          final_path = File.join(retry_directory, File.basename(stage_path))
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
        if(message[:message][:connection].response_state != :headers)
          code = args.delete(:code) || :ok
          args[:response_body] = 'Thanks' if code == :ok && args.empty?
          debug "Confirming #{message} with: Code: #{code.inspect} Args: #{args.inspect}"
          message[:message][:request].respond(code, args[:response_body] || args)
        else
          warn "Message was already confimed. Confirmation not sent! (#{message})"
        end
      end

      # Initialize http listener correctly based on configuration
      #
      # @param block [Proc] processing block
      # @return [Reel::Server::HTTP, Reel::Server::HTTPS]
      def build_listener(&block)
        if(args[:ssl])
          ssl_config = Smash.new(args[:ssl][key].dup)
          [:key, :cert].each do |key|
            if(ssl_config[key])
              ssl_config[key] = File.open(ssl_config.delete(key))
            end
          end
          Reel::Server::HTTPS.supervise(args[:bind], args[:port], ssl_config, &block)
        else
          Reel::Server::HTTP.supervise(args[:bind], args[:port], &block)
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
          :query => parse_query_string(req.query_string),
          :origin => req.remote_addr,
          :authentication => {}
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
        if(msg[:headers][:authorization])
          user, pass = Base64.urlsafe_decode64(
            msg[:headers][:authorization].split(' ').last
          ).split(':', 2)
          msg[:authentication] = {
            :username => user,
            :password => pass
          }
        end
        if(msg[:body].is_a?(Hash) && msg[:body][:id])
          Smash.new(
            :raw => msg,
            :content => msg[:body].to_smash
          )
        else
          msg
        end
      end

    end

  end
end
