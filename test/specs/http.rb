require 'minitest/autorun'
require 'carnivore-http'

describe 'Carnivore::Source::Http' do

  describe 'Building an HTTP based source' do

    it 'returns the source' do
      Carnivore::Source.build(
        :type => :http,
        :args => {
          :name => :http_source,
          :bind => '127.0.0.1',
          :port => '8705'
        }
      )
      t = Thread.new{ Carnivore.start! }
      source_wait
      Celluloid::Actor[:http_source].wont_be_nil
      t.terminate
    end

  end

  describe 'HTTP source based communication' do
    before do
      MessageStore.init
      Carnivore::Source.build(
        :type => :http,
        :args => {
          :name => :http_source,
          :bind => '127.0.0.1',
          :port => '8705'
        }
      ).add_callback(:store) do |message|
        MessageStore.messages.push(message[:message][:body])
      end
      @runner = Thread.new{ Carnivore.start! }
      source_wait
    end

    after do
      @runner.terminate
    end

    describe 'message transmissions' do
      it 'should accept message transmits' do
        Celluloid::Actor[:http_source].transmit('test message')
      end

      it 'should receive messages' do
        Celluloid::Actor[:http_source].transmit('test message 2')
        source_wait
        MessageStore.messages.must_include 'test message 2'
      end
    end
  end

end
