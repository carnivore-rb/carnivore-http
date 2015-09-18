require 'http'
require 'minitest/autorun'
require 'carnivore-http'



describe 'Carnivore::Source::Http' do

  before do
    MessageStore.init

    unless(@runner)
      @port = $carnivore_ports.pop
      Carnivore::Source.build(
        :type => :http_paths,
        :args => {
          :name => :fubar_source,
          :path => '/fubar',
          :method => :post,
          :bind => '127.0.0.1',
          :port => @port,
          :auto_respond => false
        }
      ).add_callback(:store) do |message|
        MessageStore.messages.push(message[:message][:body])
        message.confirm!(:response_body => 'custom response')
      end
      Carnivore::Source.build(
        :type => :http_paths,
        :args => {
          :name => :ohai_source,
          :path => '/ohai',
          :method => :get,
          :bind => '127.0.0.1',
          :port => @port
        }
      ).add_callback(:store) do |message|
        MessageStore.messages.push(message[:message][:body])
      end
      Carnivore::Source.build(
        :type => :http_paths,
        :args => {
          :name => :glob_source,
          :path => '/glob/v*/*',
          :method => :get,
          :bind => '127.0.0.1',
          :port => @port
        }
      ).add_callback(:store) do |message|
        MessageStore.messages.push(message[:message][:body])
      end
      @runner = Thread.new{ Carnivore.start! }
      source_wait
    end
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

      it 'returns the sources' do
        Carnivore::Supervisor.supervisor[:fubar_source].wont_be_nil
        Carnivore::Supervisor.supervisor[:ohai_source].wont_be_nil
      end

    end

    describe 'source message transmissions' do

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

    describe 'HTTP message transmissions' do

      it 'should receive messages and provide custom response' do
        response = HTTP.post("http://127.0.0.1:#{@port}/fubar", :body => 'test')
        response.body.to_s.must_equal 'custom response'
        source_wait{ !MessageStore.messages.empty? }
        MessageStore.messages.pop.must_equal 'test'
      end

      it 'should receive messages and provide default response' do
        response = HTTP.get("http://127.0.0.1:#{@port}/ohai")
        source_wait{ !MessageStore.messages.empty? }
        response.body.to_s.must_equal 'So long and thanks for all the fish!'
        MessageStore.messages.pop.must_be :empty?
      end

      it 'should receive messages via glob matching' do
        response = HTTP.get("http://127.0.0.1:#{@port}/glob/v2/things")
        source_wait{ !MessageStore.messages.empty? }
        response.body.to_s.must_equal 'So long and thanks for all the fish!'
        MessageStore.messages.pop.must_be :empty?
      end

    end
  end

end
