require 'bogo'
require 'carnivore-http/http'

module Carnivore
  class Source

    # Carnivore HTTP paths
    class HttpPaths < HttpSource

      finalizer :halt_listener
      include Bogo::Memoization

      # @return [String] end point path
      attr_reader :http_path
      # @return [Symbol] http method
      attr_reader :http_method

      # Kill listener on shutdown
      def halt_listener
        listener = memoize("#{args[:bind]}-#{args[:port]}", :global){ nil }
        if(listener && listener.alive?)
          listener.terminate
        end
        unmemoize("#{args[:bind]}-#{args[:port]}", :global)
        unmemoize("#{args[:bind]}-#{args[:port]}-queues", :global)
      end

      # Setup message queue for source
      def setup(*_)
        @http_path = args.fetch(:path, '/')
        @http_method = args.fetch(:method, 'get').to_s.downcase.to_sym
        if(message_queues[queue_key])
          raise ArgumentError.new "Conflicting HTTP path source provided! path: #{http_path} method: #{http_method}"
        else
          message_queues[queue_key] = Queue.new
        end
        super
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
          build_listener do |con|
            con.each_request do |req|
              begin
                msg = build_message(con, req)
                msg_queue = message_queues["#{req.path}-#{req.method.to_s.downcase}"]
                if(msg_queue)
                  if(authorized?(msg))
                    msg_queue << msg
                    req.respond(:ok, 'So long and thanks for all the fish!')
                  else
                    req.respond(:unauthorized, 'You are not authorized to perform requested action!')
                  end
                else
                  req.respond(:not_found, 'Requested path not found!')
                end
              rescue => e
                req.respond(:bad_request, "Failed to process request -> #{e}")
              end
            end
          end
        end
      end

      # @return [Object]
      def receive(*_)
        val = nil
        until(val)
          val = Celluloid::Future.new{ message_queue.pop }.value
        end
        val
      end

    end
  end
end
