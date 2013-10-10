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

      def transmit(message, orignal_message_or_connection, args={})
        if(original_message_or_connection.is_a?(Message))
          con = original_message_or_connection[:connection]
        else
          con = original_message_or_connection[:connection]
        end
        # TODO: add `args` options for marshaling: json/xml/etc
        con.respond(args[:code] || :ok, message)
      end

      def process(*process_args)
        srv = Reel::Server.supervise(args[:bind], args[:port]) do |con|
          while(req = con.request)
            begin
              msg = format(:request => req, :body => req.body, :connection => con)
              callbacks.each do |name|
                c_name = callback_name(name)
                debug "Dispatching message<#{msg[:message].object_id}> to callback<#{name} (#{c_name})>"
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
