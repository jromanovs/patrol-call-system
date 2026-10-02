require "rails_helper"

RSpec.describe MapBuild do
  # Stands in for curl, unzip and tilemaker: writes the file each command
  # would write, remembers the commands and the profile tilemaker got, and
  # fails, after writing, for a program named in `failing` — as a program
  # cut short leaves a partial file behind.
  let(:runner_class) do
    Struct.new(:commands, :failing, :config) do
      def call(*command, **)
        commands << command
        case command.first
        when "curl" then File.write(command[command.index("--output") + 1], "data")
        when "unzip" then File.write(File.join(command.last, "water_polygons.shp"), "shapes")
        when "tilemaker"
          self.config = JSON.parse(File.read(command[command.index("--config") + 1]))
          File.write(command[command.index("--output") + 1], "data")
        end
        !failing.include?(command.first)
      end
    end
  end

  let(:folder) { Pathname(Dir.mktmpdir) }
  let(:runner) { runner_class.new([], [], nil) }
  let(:water) { folder.join("sources/water") }

  after { FileUtils.remove_entry(folder) }

  def build(at: Time.zone.local(2026, 10, 2, 3, 0), force: false)
    travel_to(at) { described_class.new(folder:, runner:).call(force:) }
  end

  def published = folder.join("published").children.map { |path| path.basename.to_s }.sort

  def programs = runner.commands.map(&:first)

  def option(command, name) = command[command.index(name) + 1]

  it "builds the map of Latvia from the extract and the sea, with the work on disk (STO-06)",
     :aggregate_failures do
    result = build

    expect(result).to have_attributes(status: :built, file: "latvia-2026-10-02T000000Z.pmtiles")
    expect(published).to eq([ "latvia-2026-10-02T000000Z.pmtiles" ])
    expect(programs).to eq(%w[ curl curl unzip tilemaker ])
    tilemaker = runner.commands.last
    expect([ option(tilemaker, "--store"), option(tilemaker, "--process") ])
      .to eq([ folder.join("work/store").to_s, Rails.root.join("config/map/process.lua").to_s ])
    expect(runner.config.dig("layers", "ocean", "source")).to eq(water.join("water_polygons.shp").to_s)
    expect([ water.join("water_polygons.shp").exist?, folder.join("work").exist? ]).to eq([ true, false ])
  end

  it "gives every download an end, so a stalled one cannot hold the build" do
    build

    expect(runner.commands.select { |command| command.first == "curl" }.map { |curl| option(curl, "--max-time") })
      .to eq(%w[ 3600 3600 ])
  end

  it "does nothing while the map is younger than 30 days, and builds on the 30th day", :aggregate_failures do
    build

    expect(build(at: Time.zone.local(2026, 10, 31, 3, 0)).status).to eq(:up_to_date)
    expect(build(at: Time.zone.local(2026, 11, 1, 3, 0)).status).to eq(:built)
  end

  it "keeps the sea of the year and the previous map for pages still open, removes older maps", :aggregate_failures do
    build
    runner.commands.clear

    build(at: Time.zone.local(2026, 11, 1, 3, 0))
    expect(programs).to eq(%w[ curl tilemaker ])
    expect(published).to eq([ "latvia-2026-10-02T000000Z.pmtiles", "latvia-2026-11-01T010000Z.pmtiles" ])

    build(at: Time.zone.local(2026, 12, 1, 3, 0))
    expect(published).to eq([ "latvia-2026-11-01T010000Z.pmtiles", "latvia-2026-12-01T010000Z.pmtiles" ])
  end

  it "downloads the sea again a year after the last download" do
    build
    FileUtils.touch(water.join(".downloaded"), mtime: Time.zone.local(2025, 9, 1).to_time)
    runner.commands.clear

    build(at: Time.zone.local(2026, 11, 1, 3, 0))
    expect(programs).to eq(%w[ curl curl unzip tilemaker ])
  end

  it "keeps the previous map when tilemaker fails, and gives the last line of its log", :aggregate_failures do
    build
    runner.failing << "tilemaker"
    allow(runner).to receive(:call).and_wrap_original do |call, *command, **options|
      folder.join("build.log").write("reading\nout of memory\n") if command.first == "tilemaker"
      call.call(*command, **options)
    end

    result = build(at: Time.zone.local(2026, 11, 1, 3, 0))

    expect(result).to have_attributes(status: :failed, reason: "tilemaker failed: out of memory")
    expect(published).to eq([ "latvia-2026-10-02T000000Z.pmtiles" ])
  end

  it "keeps the previous map and no partial extract when the download fails", :aggregate_failures do
    build
    runner.failing << "curl"

    expect(build(at: Time.zone.local(2026, 11, 1, 3, 0)).reason).to eq("download of the Latvia extract failed")
    expect(published).to eq([ "latvia-2026-10-02T000000Z.pmtiles" ])
    expect(folder.join("work")).not_to exist
  end

  it "keeps last year's sea when the new one fails to unpack", :aggregate_failures do
    build
    sea = water.join("water_polygons.shp").tap { |file| file.write("last year's sea") }
    downloaded = Time.zone.local(2025, 9, 1).to_time
    FileUtils.touch(water.join(".downloaded"), mtime: downloaded)
    runner.failing << "unzip"

    expect(build(at: Time.zone.local(2026, 11, 1, 3, 0)).status).to eq(:failed)
    expect([ sea.exist? && sea.read, water.join(".downloaded").mtime ]).to eq([ "last year's sea", downloaded ])
    expect(published).to eq([ "latvia-2026-10-02T000000Z.pmtiles" ])
  end

  it "takes no sea from an unzip cut short, and downloads it again next time", :aggregate_failures do
    runner.failing << "unzip"

    expect(build.reason).to eq("unzip of the water polygons failed")
    expect([ water.exist?, folder.join("work").exist? ]).to eq([ false, false ])

    runner.failing.clear
    runner.commands.clear
    build(at: Time.zone.local(2026, 10, 2, 4, 0))
    expect(programs).to eq(%w[ curl curl unzip tilemaker ])
  end

  it "builds whenever asked, under a new name even on the same day", :aggregate_failures do
    build

    expect(build(at: Time.zone.local(2026, 10, 2, 9, 30), force: true).file).to eq("latvia-2026-10-02T063000Z.pmtiles")
    expect(published.size).to eq(2)
  end

  it "names each build by its UTC time to the second, so a later build sorts later, also when clocks go back",
     :aggregate_failures do
    build(at: Time.utc(2026, 10, 25, 0, 30, 0)) # 03:30 summer time in Riga
    build(at: Time.utc(2026, 10, 25, 0, 30, 20), force: true)
    build(at: Time.utc(2026, 10, 25, 1, 10, 0), force: true) # 03:10 winter time, an hour later

    expect(published).to eq(%w[ latvia-2026-10-25T003020Z.pmtiles latvia-2026-10-25T011000Z.pmtiles ])
    expect(described_class.new(folder:).current).to eq("latvia-2026-10-25T011000Z.pmtiles")
  end

  it "never runs two builds at the same time" do
    folder.join("build.lock").open(File::RDWR | File::CREAT) do |lock|
      lock.flock(File::LOCK_EX)

      expect(build.status).to eq(:busy)
    end
  end

  it "names the current map, none before the first build, without making folders", :aggregate_failures do
    expect(described_class.new(folder:).current).to be_nil
    expect(folder.join("published")).not_to exist

    build

    expect(described_class.new(folder:).current).to eq("latvia-2026-10-02T000000Z.pmtiles")
  end
end
