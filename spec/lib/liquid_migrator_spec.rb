require 'spec_helper'

describe LiquidMigrator do
  describe "converting JSONPath strings" do
    it "should work" do
      LiquidMigrator.convert_string("$.data", true).should == "{{data}}"
      LiquidMigrator.convert_string("$.data.test", true).should == "{{data.test}}"
      LiquidMigrator.convert_string("$first_title", true).should == "{{first_title}}"
    end

    it "should ignore strings which just contain a JSONPath" do
      LiquidMigrator.convert_string("$.data").should == "$.data"
      LiquidMigrator.convert_string("$first_title").should == "$first_title"
      LiquidMigrator.convert_string(" $.data", true).should == " $.data"
      LiquidMigrator.convert_string("lorem $.data", true).should == "lorem $.data"
    end
    it "should raise an exception when encountering complex JSONPaths" do
      expect { LiquidMigrator.convert_string("$.data.test.*", true) }.
        to raise_error("JSONPath '$.data.test.*' is too complex, please check your migration.")
    end
  end

  describe "converting escaped JSONPath strings" do
    it "should work" do
      LiquidMigrator.convert_string("Weather looks like <$.conditions> according to the forecast at <$.pretty_date.time>").should ==
                                    "Weather looks like {{conditions}} according to the forecast at {{pretty_date.time}}"
    end

    it "should convert the 'escape' method correctly" do
      LiquidMigrator.convert_string("Escaped: <escape $.content.name>\nNot escaped: <$.content.name>").should ==
                                    "Escaped: {{content.name | uri_escape}}\nNot escaped: {{content.name}}"
    end

    it "should raise an exception when encountering complex JSONPaths" do
      expect { LiquidMigrator.convert_string("Received <$.content.text.*> from <$.content.name> .") }.
        to raise_error("JSONPath '$.content.text.*' is too complex, please check your migration.")
    end
  end

  describe "migrating a hash" do
    it "should convert every attribute" do
      LiquidMigrator.convert_hash({'a' => "$.data", 'b' => "This is a <$.test>"}).should ==
                                  {'a' => "$.data", 'b' => "This is a {{test}}"}
    end
    it "should work with leading_dollarsign_is_jsonpath" do
      LiquidMigrator.convert_hash({'a' => "$.data", 'b' => "This is a <$.test>"}, leading_dollarsign_is_jsonpath: true).should ==
                                  {'a' => "{{data}}", 'b' => "This is a {{test}}"}
    end
    it "should use the corresponding *_path attributes when using merge_path_attributes"do
      LiquidMigrator.convert_hash({'a' => "default", 'a_path' => "$.data"}, {leading_dollarsign_is_jsonpath: true, merge_path_attributes: true}).should ==
                                  {'a' => "{{data}}"}
    end
    it "should raise an exception when encountering complex JSONPaths" do
      expect { LiquidMigrator.convert_hash({'b' => "This is <$.complex[2]>"}) }.
        to raise_error("JSONPath '$.complex[2]' is too complex, please check your migration.")
    end
  end

  describe "migrating the 'make_message' format" do
    it "should work" do
      LiquidMigrator.convert_make_message('<message>').should == '{{message}}'
      LiquidMigrator.convert_make_message('<new.message>').should == '{{new.message}}'
      LiquidMigrator.convert_make_message('Hello <world>. How is <nested.life>').should == 'Hello {{world}}. How is {{nested.life}}'
    end
  end

  describe "migrating an actual agent" do
    before do
      valid_params = {
                        'auth_token' => 'token',
                        'room_name' => 'test',
                        'room_name_path' => '',
                        'username' => "Huginn",
                        'username_path' => '$.username',
                        'message' => "Hello from Huginn!",
                        'message_path' => '$.message',
                        'notify' => false,
                        'notify_path' => '',
                        'color' => 'yellow',
                        'color_path' => '',
                      }

      @agent = Agents::HipchatAgent.new(:name => "somename", :options => valid_params)
      @agent.user = users(:jane)
      @agent.save!
    end

    it "should work" do
      LiquidMigrator.convert_all_agent_options(@agent)
      @agent.reload.options.should == {"auth_token" => 'token', 'color' => 'yellow', 'notify' => false, 'room_name' => 'test', 'username' => '{{username}}', 'message' => '{{message}}'}
    end

    it "should work with nested hashes" do
      @agent.options['very'] = {'nested' => '$.value'}
      LiquidMigrator.convert_all_agent_options(@agent)
      @agent.reload.options.should == {"auth_token" => 'token', 'color' => 'yellow', 'very' => {'nested' => '{{value}}'}, 'notify' => false, 'room_name' => 'test', 'username' => '{{username}}', 'message' => '{{message}}'}
    end

    it "should work with nested arrays" do
      @agent.options['array'] = ["one", "$.two"]
      LiquidMigrator.convert_all_agent_options(@agent)
      @agent.reload.options.should == {"auth_token" => 'token', 'color' => 'yellow', 'array' => ['one', '{{two}}'], 'notify' => false, 'room_name' => 'test', 'username' => '{{username}}', 'message' => '{{message}}'}
    end

    it "should raise an exception when encountering complex JSONPaths" do
      @agent.options['username_path'] = "$.very.complex[*]"
      expect { LiquidMigrator.convert_all_agent_options(@agent) }.
        to raise_error("JSONPath '$.very.complex[*]' is too complex, please check your migration.")
    end

    it "should work with the human task agent" do
      valid_params = {
        'expected_receive_period_in_days' => 2,
        'trigger_on' => "event",
        'hit' =>
          {
            'assignments' => 1,
            'title' => "Sentiment evaluation",
            'description' => "Please rate the sentiment of this message: '<$.message>'",
            'reward' => 0.05,
            'lifetime_in_seconds' => 24 * 60 * 60,
            'questions' =>
              [
                {
                  'type' => "selection",
                  'key' => "sentiment",
                  'name' => "Sentiment",
                  'required' => "true",
                  'question' => "Please select the best sentiment value:",
                  'selections' =>
                    [
                      { 'key' => "happy", 'text' => "Happy" },
                      { 'key' => "sad", 'text' => "Sad" },
                      { 'key' => "neutral", 'text' => "Neutral" }
                    ]
                },
                {
                  'type' => "free_text",
                  'key' => "feedback",
                  'name' => "Have any feedback for us?",
                  'required' => "false",
                  'question' => "Feedback",
                  'default' => "Type here...",
                  'min_length' => "2",
                  'max_length' => "2000"
                }
              ]
          }
      }
      @agent = Agents::HumanTaskAgent.new(:name => "somename", :options => valid_params)
      @agent.user = users(:jane)
      LiquidMigrator.convert_all_agent_options(@agent)
      @agent.reload.options['hit']['description'].should == "Please rate the sentiment of this message: '{{message}}'"
    end
  end
end