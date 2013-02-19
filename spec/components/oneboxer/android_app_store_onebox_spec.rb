# encoding: utf-8

require 'spec_helper'
require 'oneboxer'
require 'oneboxer/android_app_store_onebox'

describe Oneboxer::AndroidAppStoreOnebox do 
  before(:each) do
    @o = Oneboxer::AndroidAppStoreOnebox.new("https://play.google.com/store/apps/details?id=com.moosoft.parrot")
    FakeWeb.register_uri(:get, @o.translate_url, :response => fixture_file('oneboxer/android.response'))
  end
  
  it "generates the expected onebox for Android App Store" do
    html = Nokogiri::HTML("<body>" + @o.onebox + "</body>")

    html.at_xpath("html/body/div")["class"].should == "onebox-result"
    html.at_xpath("html/body/div/div[1]")["class"].should == "source"
    html.at_xpath("html/body/div/div[1]/div")["class"].should == "info"
    html.at_xpath("html/body/div/div[1]/div/a")["href"].should == "https://play.google.com/store/apps/details?id=com.moosoft.parrot"
    html.at_xpath("html/body/div/div[1]/div/a")["target"].should == "_blank"
    html.at_xpath("html/body/div/div[1]/div/a/img")["class"].should == "favicon"
    html.at_xpath("html/body/div/div[1]/div/a/img")["src"].should == "/assets/favicons/google_play.png"

    html.at_xpath("html/body/div/div[2]")["class"].should == "onebox-result-body"
    html.at_xpath("html/body/div/div[2]/img")["src"].should == "https://lh5.ggpht.com/wrYYVu74XNUu2WHk0aSZEqgdCDCNti9Fl0_dJnhgR6jY04ajQgVg5ABMatfcTDsB810=w124"
    html.at_xpath("html/body/div/div[2]/img")["class"].should == "thumbnail"
    html.at_xpath("html/body/div/div[2]/h3/a")["href"].should == "https://play.google.com/store/apps/details?id=com.moosoft.parrot"
    html.at_xpath("html/body/div/div[2]/h3/a")["target"].should == "_blank"
    html.at_xpath("html/body/div/div[2]/h3/a").text.should =~ /Talking Parrot/
    html.at_xpath("html/body/div/div[2]").text.should =~ /Listen to the parrot.*A Fun application.*Upgrade to.*as your ringtone.*MENU button.*anonymous usage stats.*feedback welcome/m

    html.at_xpath("html/body/div/div[3]")["class"].should == "clearfix"
  end
end
