require "rails_helper"

RSpec.describe MapBuild do
  # Stands in for curl, unzip and tilemaker: writes the file each command
  # would write and remembers the commands and the profile tilemaker got; a
  # program named in `failing` fails.
  let(:runner_class) do
    Struct.new(:commands, :failing, :config) do
      def call(*command, **)
        commands << command
        return false if failing.include?(command.first)

        case command.first
        when "curl" then File.write(command[command.index("--output") + 1], "data")
        when "tilemaker"
          self.config = JSON.parse(File.read(command[command.index("--config") + 1]))
          File.write(command[command.index("--output") + 1], "data")
        when "unzip" then File.write(File.join(command.last, "water_polygons.shp"), "shapes")
        end
        true
      end
    end
  end

  let(:folder) { Pathname(Dir.mktmpdir) }
  let(:runner) { runner_class.new([], [], nil) }

  after { FileUtils.remove_entry(folder) }

  def build(at: Time.zone.local(2026, 10, 2, 3, 0), force: false)
    travel_to(at) { described_class.new(folder:, runner:).call(force:) }
  end

  def published = folder.join("published").children.map { |path| path.basename.to_s }.sort

  def programs = runner.commands.map(&:first)

  it "builds the dated map of Latvia from the extract and the sea, with the work stored on disk (STO-06)",
     :aggregate_failures do
    result = build

    expect(result).to have_attributes(status: :built, file: "latvia-2026-10-02.pmtiles")
    expect(published).to eq([ "latvia-2026-10-02.pmtiles" ])
    expect(programs).to eq(%w[ curl curl unzip tilemaker ])
    tilemaker = runner.commands.last
    expect(tilemaker.drop(1).each_slice(2).to_h.slice("--store", "--process"))
      .to eq("--store" => folder.join("work/store").to_s, "--process" => Rails.root.join("config/map/process.lua").to_s)
    expect(runner.config.dig("layers", "ocean", "source")).to eq(folder.join("sources/water/water_polygons.shp").to_s)
    expect(folder.join("work")).not_to exist
  end

  it "does nothing while the map is younger than 30 days" do
    build

    expect(build(at: Time.zone.local(2026, 10, 31, 3, 0)).status).to eq(:up_to_date)
  end

  it "builds a new map after 30 days, keeps the sea of the year and removes the older map", :aggregate_failures do
    build
    runner.commands.clear

    expect(build(at: Time.zone.local(2026, 11, 1, 3, 0)).file).to eq("latvia-2026-11-01.pmtiles")
    expect(programs).to eq(%w[ curl tilemaker ])
    expect(published).to eq([ "latvia-2026-11-01.pmtiles" ])
  end

  it "downloads the sea again when it is older than a year" do
    build
    FileUtils.touch(folder.join("sources/water/water_polygons.shp"), mtime: Time.zone.local(2025, 9, 1).to_time)
    runner.commands.clear

    build(at: Time.zone.local(2026, 11, 1, 3, 0))
    expect(programs).to eq(%w[ curl curl unzip tilemaker ])
  end

  it "keeps the previous map when the build fails, and says why (STO-06)", :aggregate_failures do
    build
    runner.failing << "tilemaker"

    result = build(at: Time.zone.local(2026, 11, 1, 3, 0))

    expect(result).to have_attributes(status: :failed, reason: "tilemaker failed")
    expect(published).to eq([ "latvia-2026-10-02.pmtiles" ])
  end

  it "keeps the previous map when the download fails" do
    build
    runner.failing << "curl"

    expect(build(at: Time.zone.local(2026, 11, 1, 3, 0)).reason).to eq("download of the Latvia extract failed")
  end

  it "builds whenever asked, also with a young map" do
    build

    expect(build(at: Time.zone.local(2026, 10, 3, 3, 0), force: true).file).to eq("latvia-2026-10-03.pmtiles")
  end

  it "never runs two builds at the same time" do
    folder.join("build.lock").open(File::RDWR | File::CREAT) do |lock|
      lock.flock(File::LOCK_EX)

      expect(build.status).to eq(:busy)
    end
  end

  it "names the current map, none before the first build", :aggregate_failures do
    expect(described_class.new(folder:).current).to be_nil

    build

    expect(described_class.new(folder:).current).to eq("latvia-2026-10-02.pmtiles")
  end
end
