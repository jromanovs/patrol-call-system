require "rails_helper"

RSpec.describe CallPhoto do
  include_context "without the seeded records"

  let(:jpeg) { file_fixture("photo.jpg").binread }

  def photo(name, content_type = nil, io: file_fixture(name).open)
    build(:call_photo, image: { io:, filename: name, content_type: })
  end

  def refusal(record) = record.tap(&:validate).errors[:base]

  it { is_expected.to belong_to(:call) }
  it { is_expected.to belong_to(:user) }

  it "takes a JPEG, PNG or WebP image (CRW-10)", :aggregate_failures do
    %w[ photo.jpg photo.png photo.webp ].each { |name| expect(photo(name)).to be_valid }
  end

  it "refuses any other file, also one named and declared a photo (CRW-10)", :aggregate_failures do
    [ photo("photo.gif"), photo("note.txt"), photo("note.jpg", "image/jpeg", io: file_fixture("note.txt").open) ].each do |record|
      expect(refusal(record)).to eq([ "Photo must be a JPEG, PNG or WebP image of at most 5 MB" ])
    end
  end

  it "takes an image of 5 MB and refuses a larger one (CRW-10)", :aggregate_failures do
    expect(photo("five.jpg", io: StringIO.new(jpeg + ("\0" * (5.megabytes - jpeg.bytesize))))).to be_valid
    expect(refusal(photo("more.jpg", io: StringIO.new(jpeg + ("\0" * (5.megabytes - jpeg.bytesize + 1))))))
      .to eq([ "Photo must be a JPEG, PNG or WebP image of at most 5 MB" ])
  end

  it "needs an image" do
    expect(build(:call_photo, image: nil)).not_to be_valid
  end

  it "goes with its call, its file too (BR-19)", :aggregate_failures do
    call = create(:call_photo).call
    call.update_column(:status, Call.statuses[:closed])

    expect { call.destroy }.to change(described_class, :count).by(-1).and change(ActiveStorage::Attachment, :count).by(-1)
  end
end
