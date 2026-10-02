# STO-06: the vector tile file (PMTiles) of Latvia, built by tilemaker from the
# Geofabrik extract, with the sea from the OSM water polygons. The folder lives
# outside public/: only published/ is served, at /tiles; the sources and the
# work stay private. Everything is downloaded and built in work/ and moved into
# place only after it succeeded, so a step cut short leaves the last good map
# and the last good sea as they were.
class MapBuild
  EXTRACT = "https://download.geofabrik.de/europe/latvia-latest.osm.pbf".freeze
  WATER = "https://osmdata.openstreetmap.de/download/water-polygons-split-4326.zip".freeze
  FOLDER = Rails.root.join("storage/map")
  PROFILE = Rails.root.join("config/map")
  MAP_AGE = 30.days
  WATER_AGE = 1.year
  # A download that takes longer, or stalls below 10 kB/s for 2 minutes,
  # fails instead of holding the build.
  DOWNLOAD_LIMITS = %w[ --max-time 3600 --speed-limit 10000 --speed-time 120 ].freeze
  # The map before the current one stays for pages opened before the build.
  KEPT_MAPS = 2

  Result = Data.define(:status, :file, :reason) do
    def failed? = status == :failed
  end

  class Failed < StandardError; end

  def initialize(folder: FOLDER, runner: method(:run))
    @folder = Pathname(folder)
    @runner = runner
  end

  # The file to show, or nil before the first build.
  def current = maps.last&.basename&.to_s

  # The age is checked under the lock: a build that starts as another one
  # ends sees the new map.
  def call(force: false) = locked { force || due? ? build : up_to_date }

  private

  def maps = @folder.join("published").glob("latvia-*.pmtiles").sort

  def up_to_date = Result.new(status: :up_to_date, file: current, reason: nil)

  def due?
    date = current&.then { |name| Date.parse(name[/\d{4}-\d{2}-\d{2}/]) }
    date.nil? || date <= MAP_AGE.ago.to_date
  end

  # A second build while one runs does nothing.
  def locked
    @folder.mkpath
    @folder.join("build.lock").open(File::RDWR | File::CREAT) do |lock|
      return Result.new(status: :busy, file: current, reason: nil) unless lock.flock(File::LOCK_EX | File::LOCK_NB)

      yield
    end
  end

  def build
    FileUtils.rm_rf(work)
    name = "latvia-#{Time.current.strftime('%Y-%m-%dT%H%M')}.pmtiles"
    step("download of the Latvia extract") { download(EXTRACT, folder("work").join("latvia.osm.pbf")) }
    refresh_water if water_due?
    step("tilemaker") { tilemaker(folder("work").join(name)) }
    publish(work.join(name), name)
    Result.new(status: :built, file: name, reason: nil)
  rescue Failed => failure
    Result.new(status: :failed, file: current, reason: failure.message)
  ensure
    FileUtils.rm_rf(work)
  end

  def step(name)
    return if yield

    last_line = log.exist? ? log.readlines.map(&:strip).reject(&:empty?).last : nil
    raise Failed, [ "#{name} failed", last_line ].compact.join(": ")
  end

  def water = @folder.join("sources/water")

  def water_due?
    stamp = water.join(".downloaded")
    !stamp.exist? || stamp.mtime <= WATER_AGE.ago
  end

  # The new sea replaces the old one only when it unpacked whole.
  def refresh_water
    archive = folder("work").join("water.zip")
    unpacked = folder("work/water")
    step("download of the water polygons") { download(WATER, archive) }
    step("unzip of the water polygons") { @runner.call("unzip", "-q", "-o", "-j", archive.to_s, "-d", unpacked.to_s) }
    FileUtils.rm_rf(water)
    FileUtils.mv(unpacked, folder("sources").join("water"))
    FileUtils.touch(water.join(".downloaded"))
  end

  def download(url, path)
    @runner.call("curl", "--fail", "--silent", "--show-error", "--location", *DOWNLOAD_LIMITS,
                 "--output", path.to_s, url)
  end

  def tilemaker(output)
    @runner.call("tilemaker", "--input", work.join("latvia.osm.pbf").to_s, "--output", output.to_s,
                 "--config", config.to_s, "--process", PROFILE.join("process.lua").to_s,
                 "--store", folder("work/store").to_s)
  end

  # The profile with the sea read from this folder.
  def config
    profile = JSON.parse(PROFILE.join("config.json").read)
    profile["layers"]["ocean"]["source"] = water.join("water_polygons.shp").to_s
    work.join("config.json").tap { |path| path.write(JSON.generate(profile)) }
  end

  def publish(built, name)
    FileUtils.mv(built, folder("published").join(name))
    maps[0...-KEPT_MAPS].each(&:delete)
  end

  def work = @folder.join("work")

  def log = @folder.join("build.log")

  def folder(name) = @folder.join(name).tap(&:mkpath)

  def run(*command) = system(*command, out: File::NULL, err: log.to_s)
end
