require 'http'
require 'minitest/autorun'
require 'carnivore-http'
require 'pry'

describe 'Carnivore::Source::Http' do

  before do
    MessageStore.init
    @port = $carnivore_ports.pop
    Carnivore::Source.build(
      :type => :http,
      :args => {
        :name => :http_source,
        :bind => '127.0.0.1',
        :port => @port
      }
    ).add_callback(:store) do |message|
      MessageStore.messages.push(message[:message][:body])
      message.confirm!
    end
    @runner = Thread.new{ Carnivore.start! }
    source_wait
  end

  after do
    Carnivore::Supervisor.supervisor.registry.values.map(&:terminate)
    Carnivore::Supervisor.supervisor.registry.clear
  end

  describe 'HTTP source based communication' do

    before do
      MessageStore.messages.clear
    end

    describe 'Building an HTTP based source' do

      it 'returns the source' do
        Carnivore::Supervisor.supervisor[:http_source].wont_be_nil
      end

    end

    describe 'message transmissions' do

      it 'should accept message transmits' do
        Carnivore::Supervisor.supervisor[:http_source].transmit('test message')
      end

      it 'should receive messages' do
        Carnivore::Supervisor.supervisor[:http_source].transmit('test message 2')
        source_wait(2) do
          !MessageStore.messages.empty?
        end
        MessageStore.messages.wont_be_empty
        MessageStore.messages.pop.must_equal 'test message 2'
      end

      it 'should accept http requests' do
        HTTP.get("http://127.0.0.1:#{@port}/")
        source_wait(2) do
          !MessageStore.messages.empty?
        end
        MessageStore.messages.wont_be_empty
        MessageStore.messages.pop.wont_be_nil
      end

    end
  end

end
