# STO-06: the vector tile file (PMTiles) of Latvia, built by tilemaker from the
# Geofabrik extract, with the sea from the OSM water polygons. The folder lives
# outside public/: only published/ is served, at /tiles; the sources and the
# work stay private. A new file, named by its date, replaces the previous one
# only after a successful build.
class MapBuild
  EXTRACT = "https://download.geofabrik.de/europe/latvia-latest.osm.pbf".freeze
  WATER = "https://osmdata.openstreetmap.de/download/water-polygons-split-4326.zip".freeze
  FOLDER = Rails.root.join("storage/map")
  PROFILE = Rails.root.join("config/map")
  MAP_AGE = 30.days
  WATER_AGE = 1.year

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

  def call(force: false)
    return Result.new(status: :up_to_date, file: current, reason: nil) unless force || due?

    locked { build }
  end

  private

  def maps = folder("published").glob("latvia-*.pmtiles").sort

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
    name = "latvia-#{Date.current.iso8601}.pmtiles"
    work = folder("work")
    step("download of the Latvia extract") { download(EXTRACT, folder("sources").join("latvia.osm.pbf")) }
    refresh_water if water_due?
    step("tilemaker") { tilemaker(work.join(name)) }
    publish(work.join(name), name)
    Result.new(status: :built, file: name, reason: nil)
  rescue Failed => failure
    Result.new(status: :failed, file: current, reason: failure.message)
  ensure
    FileUtils.rm_rf(@folder.join("work"))
  end

  def step(name)
    raise Failed, "#{name} failed" unless yield
  end

  def water_due?
    shapes = folder("sources").join("water/water_polygons.shp")
    !shapes.exist? || shapes.mtime <= WATER_AGE.ago
  end

  def refresh_water
    archive = folder("sources").join("water.zip")
    step("download of the water polygons") { download(WATER, archive) }
    step("unzip of the water polygons") do
      @runner.call("unzip", "-q", "-o", "-j", archive.to_s, "-d", folder("sources/water").to_s)
    end
  ensure
    archive&.delete if archive&.exist?
  end

  def download(url, path)
    @runner.call("curl", "--fail", "--silent", "--show-error", "--location", "--output", path.to_s, url)
  end

  def tilemaker(output)
    @runner.call("tilemaker", "--input", folder("sources").join("latvia.osm.pbf").to_s, "--output", output.to_s,
                 "--config", config.to_s, "--process", PROFILE.join("process.lua").to_s,
                 "--store", folder("work/store").to_s)
  end

  # The profile with the sea read from this folder.
  def config
    profile = JSON.parse(PROFILE.join("config.json").read)
    profile["layers"]["ocean"]["source"] = folder("sources").join("water/water_polygons.shp").to_s
    folder("work").join("config.json").tap { |path| path.write(JSON.generate(profile)) }
  end

  def publish(built, name)
    FileUtils.mv(built, folder("published").join(name))
    maps.reject { |path| path.basename.to_s == name }.each(&:delete)
  end

  def folder(name) = @folder.join(name).tap(&:mkpath)

  def run(*command) = system(*command, out: File::NULL, err: @folder.join("build.log").to_s)
end
