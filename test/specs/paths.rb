require 'http'
require 'minitest/autorun'
require 'carnivore-http'


describe 'Carnivore::Source::Http' do

  before do
    MessageStore.init

    unless(@runner)
      Carnivore::Source.build(
        :type => :http_paths,
        :args => {
          :name => :fubar_source,
          :path => '/fubar',
          :method => :post,
          :bind => '127.0.0.1',
          :port => '8706'
        }
      ).add_callback(:store) do |message|
        MessageStore.messages.push(message[:message][:body])
        message.confirm!
      end
      Carnivore::Source.build(
        :type => :http_paths,
        :args => {
          :name => :ohai_source,
          :path => '/ohai',
          :method => :get,
          :bind => '127.0.0.1',
          :port => '8706'
        }
      ).add_callback(:store) do |message|
        MessageStore.messages.push(message[:message][:body])
        message.confirm!
      end
      @runner = Thread.new{ Carnivore.start! }
      source_wait
    end
  end

  after do
    @runner.terminate
  end

  describe 'HTTP source based communication' do

    before do
      MessageStore.messages.clear
    end

    describe 'Building an HTTP based source' do

      it 'returns the sources' do
        Carnivore::Supervisor.supervisor[:fubar_source].wont_be_nil
        Carnivore::Supervisor.supervisor[:ohai_source].wont_be_nil
      end

    end

    describe 'message transmissions' do

      it 'should accept message transmits' do
        Carnivore::Supervisor.supervisor[:fubar_source].transmit('test message')
        Carnivore::Supervisor.supervisor[:ohai_source].transmit('test message')
      end

      it 'should receive messages' do
        Carnivore::Supervisor.supervisor[:fubar_source].transmit('test message to fubar')
        source_wait(4) do
          !MessageStore.messages.empty?
        end
        MessageStore.messages.wont_be_empty
        MessageStore.messages.pop.must_equal 'test message to fubar'
        Carnivore::Supervisor.supervisor[:ohai_source].transmit('test message to ohai')
        source_wait(4) do
          !MessageStore.messages.empty?
        end
        MessageStore.messages.wont_be_empty
        MessageStore.messages.pop.must_equal 'test message to ohai'
      end

    end
  end

end
