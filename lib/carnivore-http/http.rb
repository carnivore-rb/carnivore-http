require 'carnivore-http'

module Carnivore
  class Source
    class Http < HttpSource

      # Process requests
      def process(*process_args)
        unless(@processing)
          @processing = true
          srv = build_listener do |req|
            begin
              msg = build_message(req)
              msg = format(msg)
              if(authorized?(msg))
                callbacks.each do |name|
                  c_name = callback_name(name)
                  debug "Dispatching #{msg} to callback<#{name} (#{c_name})>"
                  callback_supervisor[c_name].call(msg)
                end
                req.respond(:ok, 'So long, and thanks for all the fish!') if args[:auto_respond]
              else
                req.respond(:unauthorized, 'You are not authorized to perform requested action!')
              end
            rescue => e
              req.respond(:bad_request, "Failed to process request -> #{e}")
            end
          end
          true
        else
          false
        end
      end

    end

  end
end
