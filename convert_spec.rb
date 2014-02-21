require_relative './spec_helper.rb'
require_relative './convert.rb'

describe Rate do
  it "should parse attributes from rates XML" do
    xml = "<rate><from>AUD</from><to>CAD</to><conversion>1.0079</conversion></rate>"
    subject.parse(Nokogiri::XML(xml))
    subject.from.should       == 'AUD'
    subject.to.should         == 'CAD'
    subject.conversion.should == 1.0079
  end

  it "should create rate objects from a rates XML file" do
    rates = Rate.load('RATES.xml')
    rates.first.from.should == 'AUD'
    rates.size.should       == 6
  end
end

describe Transaction do
  it "should create transaction objects from a CSV file" do
    txns = Transaction.load('SAMPLE_TRANS.csv')
    txns.first.store.should    == 'Yonkers'
    txns.first.sku.should      == 'DM1210'
    txns.first.amount.should   == BigDecimal.new('70.00')
    txns.first.currency.should == 'USD'
    txns.size.should           == 5
  end
end

describe Convert do
  it "should perform a bankers round" do
    subject.bankers_round(23.0350).should == 23.04
    subject.bankers_round(23.0450).should == 23.04
    subject.bankers_round(23.1).should    == 23.1
  end

  describe "creating an array of conversions from any currency to USD" do
    let(:aud_cad) { Rate.new({:from => 'AUD', :to => 'CAD'}) }
    let(:aud_eur) { Rate.new({:from => 'AUD', :to => 'EUR'}) }
    let(:cad_aud) { Rate.new({:from => 'CAD', :to => 'AUD'}) }
    let(:cad_usd) { Rate.new({:from => 'CAD', :to => 'USD'}) }
    let(:eur_aud) { Rate.new({:from => 'EUR', :to => 'AUD'}) }
    let(:usd_cad) { Rate.new({:from => 'USD', :to => 'CAD'}) }
    let(:all_rates) { [aud_cad, aud_eur, cad_aud, cad_usd, eur_aud, usd_cad] }
    before { subject.rates = all_rates }

    it "should find a direct conversion" do
      subject.conversions_to_usd('CAD').should == [cad_usd]
    end

    it "should find conversion chains" do
      subject.conversions_to_usd('AUD').should == [
        aud_cad, cad_usd
      ]

      subject.conversions_to_usd('EUR').should == [
        eur_aud, aud_cad, cad_usd
      ]
    end
  end

  it "should convert transactions from other currencies into USD" do
    subject.rates << Rate.new({:from => 'AUD', :to => 'CAD', :conversion => 1.0079 })
    subject.rates << Rate.new({:from => 'CAD', :to => 'USD', :conversion => 1.0090 })
    subject.convert(54.64, 'USD').should == 54.64
    subject.convert(19.68, 'AUD').should == 20.01
    subject.convert(58.58, 'AUD').should == 59.57
  end

  it "should calculate the correct amount for the sample files" do
    subject.total('SAMPLE_TRANS.csv', 'SAMPLE_RATES.xml', 'DM1182').should == 134.22
  end
end

