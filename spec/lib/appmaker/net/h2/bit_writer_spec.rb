require 'appmaker'

describe Appmaker::Net::H2::BitWriter do
  subject { described_class.new }

  describe '#write_prefixed_int' do
    let(:expected_bytes) do
      [
        0b01000000 | 5,
        89
      ]
    end

    it 'produces expected bytes' do
      subject.write_bit(0)
      subject.write_bit(1)
      subject.write_prefixed_int(5, 5)
      subject.write_byte(89)

      expect(subject_bytes).to eq(expected_bytes)
    end

    context 'when number spans multiple bytes' do
      let(:expected_bytes) { [95, 241, 203, 159, 45, 21] }

      it 'produces expected bytes' do
        subject.write_bit(0)
        subject.write_bit(1)
        subject.write_prefixed_int(94889488, 5)
        subject.write_byte(21)

        expect(subject_bytes).to eq(expected_bytes)
      end
    end
  end

  describe '#write_byte' do
    let(:expected_bytes) do
      [0, 1, 2, 255, 127, 254]
    end

    it 'produces expected bytes' do
      subject.write_byte(0)
      subject.write_byte(1)
      subject.write_byte( 2)
      subject.write_byte(255)
      subject.write_byte( 127)
      subject.write_byte(254)

      expect(subject_bytes).to eq(expected_bytes)
    end
  end

  describe '#write_int16' do
    let(:expected_bytes) do
      [76, 246]
    end

    it 'produces expected bytes' do
      subject.write_int16(19702)

      expect(subject_bytes).to eq(expected_bytes)
    end
  end

  describe '#write_int24' do
    let(:expected_bytes) do
      [28, 8, 182]
    end

    it 'produces expected bytes' do
      subject.write_int24(1837238)

      expect(subject_bytes).to eq(expected_bytes)
    end
  end

  describe '#write_int32' do
    let(:expected_bytes) do
      [127, 255, 255, 255]
    end

    it 'produces expected bytes' do
      subject.write_int32(2147483647)

      expect(subject_bytes).to eq(expected_bytes)
    end
  end

  describe '#write_bytes' do
    let(:expected_bytes) do
      [255, 1, 4, 0, 127, 34, 98, 150]
    end
    let(:bytes) do
      "\xFF".force_encoding('ASCII-8BIT') + expected_bytes[1..-1].map(&:chr).join('')
    end

    it 'produces expected bytes' do
      subject.write_bytes(bytes)

      expect(subject_bytes).to eq(expected_bytes)
    end
  end

  describe '#write_string' do
    let(:expected_bytes) do
      [13, 72, 51, 108, 76, 111, 32, 119, 48, 114, 108, 68, 33, 33]
    end

    it 'produces expected bytes' do
      subject.write_string('H3lLo w0rlD!!')

      expect(subject_bytes).to eq(expected_bytes)
    end
  end

  private

  def subject_bytes
    array_of_bytes subject.bytes
  end

  def array_of_bytes s
    s.split('').map &:ord
  end
end
