require 'bogo'
require 'carnivore-http/http'

module Carnivore
  class Source

    # Carnivore HTTP paths
    class HttpPaths < HttpSource

      # Default max wait time for message response
      DEFAULT_RESPONSE_TIMEOUT = 10
      # Default response wait time stepping
      DEFAULT_RESPONSE_WAIT_STEP = 0.1

      include Bogo::Memoization

      # @return [String] end point path
      attr_reader :http_path
      # @return [Symbol] http method
      attr_reader :http_method

      # Kill listener on shutdown
      def terminate
        listener = memoize("#{args[:bind]}-#{args[:port]}", :global){ nil }
        if(listener && listener.running)
          listener.stop(:sync)
        end
        unmemoize("#{args[:bind]}-#{args[:port]}", :global)
        unmemoize("#{args[:bind]}-#{args[:port]}-queues", :global)
      end

      # Setup message queue for source
      def setup(*_)
        @http_path = args.fetch(:path, '/')
        @http_method = args.fetch(:method, 'get').to_s.downcase.to_sym
        super
        if(message_queues[queue_key])
          raise ArgumentError.new "Conflicting HTTP path source provided! path: #{http_path} method: #{http_method}"
        else
          message_queues[queue_key] = Smash.new(
            :queue => Queue.new
          )
        end
        message_queues[queue_key].merge!(
          Smash.new(:config => args.to_smash)
        )
      end

      # Setup the HTTP listener source
      def connect
        start_listener!
      end

      # @return [Queue] Message queue
      def message_queues
        memoize("#{args[:bind]}-#{args[:port]}-queues", :global) do
          Smash.new
        end
      end

      # @return [String]
      def queue_key
        "#{http_path}-#{http_method}"
      end

      # @return [Queue]
      def message_queue
        message_queues[queue_key]
      end

      # Start the HTTP(S) listener
      def start_listener!
        memoize("#{args[:bind]}-#{args[:port]}", :global) do
          build_listener do |req|
            begin
              msg = build_message(req)
              # Start with static path lookup since it's the
              # cheapest, then fallback to iterative globbing
              msg_queue = nil
              unless(msg_queue = message_queues["#{req.path}-#{req.method.to_s.downcase}"])
                message_queues.each do |k,v|
                  path_glob, http_method = k.split('-')
                  if(req.method.to_s.downcase == http_method && File.fnmatch(path_glob, req.path))
                    msg_queue = v
                  end
                end
              end
              if(msg_queue)
                if(authorized?(msg))
                  msg_queue[:queue] << msg
                  if(msg_queue[:config][:auto_respond])
                    code = msg_queue[:config].fetch(:response, :code, 'ok').to_sym
                    response = msg_queue[:config].fetch(:response, :message, 'So long and thanks for all the fish!')
                    req.respond(code, response)
                  end
                else
                  req.respond(:unauthorized, 'You are not authorized to perform requested action!')
                end
              else
                req.respond(:not_found, 'Requested path not found!')
              end
            rescue => e
              req.respond(:bad_request, "Failed to process request -> #{e}")
              puts "#{e}\n#{e.backtrace.join("\n")}"
            end
          end
        end
      end

      # @return [Object]
      def receive(*_)
        val = nil
        until(val)
          val = defer{ message_queue[:queue].pop }
        end
        val
      end

    end
  end
end
