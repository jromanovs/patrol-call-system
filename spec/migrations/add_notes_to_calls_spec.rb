require "rails_helper"
require Rails.root.glob("db/migrate/*_add_notes_to_calls.rb").sole

RSpec.describe AddNotesToCalls do
  include_context "without the seeded records"

  let(:migration) { described_class.new }

  # A call as it was kept before: what its closing or its cancellation
  # added stands in the description, under an English name.
  def kept(status, description)
    create(:alarm_call).tap { |call| call.update_columns(status: Call.statuses[status], description:) }
  end

  def now(call) = call.reload.attributes.values_at("description", "closing_note", "cancellation_reason")

  def move = migration.suppress_messages { migration.move }

  it "moves the note of a closed call and the reason of a cancelled one out of the description", :aggregate_failures do
    noted = kept(:closed, "Back door\nClosing note: Sensor fault")
    alone = kept(:closed, "Closing note: Sensor fault")
    reasoned = kept(:cancelled, "Back door\nCancelled: Client called back")
    move

    expect(now(noted)).to eq([ "Back door", "Sensor fault", nil ])
    expect(now(alone)).to eq([ nil, "Sensor fault", nil ])
    expect(now(reasoned)).to eq([ "Back door", nil, "Client called back" ])
  end

  it "takes a note of several lines whole, after a description of several lines" do
    several = kept(:closed, "Back door\r\nSide gate\nClosing note: Sensor fault\r\nWindow left open")
    move

    expect(now(several)).to eq([ "Back door\r\nSide gate", "Sensor fault\r\nWindow left open", nil ])
  end

  it "leaves a description that only looks alike as it is", :aggregate_failures do
    alike = { pending: "Closing note: typed by hand", closed: "Cancelled: typed by hand", cancelled: "Closing note: typed by hand" }
              .map { |status, description| kept(status, description) }
    within = kept(:closed, "See the Closing note: none yet")
    plain = kept(:closed, "Back door")
    move

    expect(alike.map { |call| now(call) }).to eq([ [ "Closing note: typed by hand", nil, nil ], [ "Cancelled: typed by hand", nil, nil ],
                                                   [ "Closing note: typed by hand", nil, nil ] ])
    expect([ now(within), now(plain) ]).to eq([ [ "See the Closing note: none yet", nil, nil ], [ "Back door", nil, nil ] ])
  end

  it "puts every line back as it was, on the way down", :aggregate_failures do
    before = { closed: [ "Back door\nClosing note: Sensor fault", "Closing note: Sensor fault\r\nWindow left open", "Back door" ],
               cancelled: [ "Back door\n\nCancelled: Client called back", "Cancelled: Client called back" ] }
    calls = before.flat_map { |status, descriptions| descriptions.map { |description| kept(status, description) } }
    move
    migration.suppress_messages { migration.put_back }

    expect(calls.map { |call| now(call) }).to eq(before.values.flatten.map { |description| [ description, nil, nil ] })
  end
end
