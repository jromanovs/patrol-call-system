# STO-05: demo data on top of the seeds. Sites at register addresses of
# public buildings with fictitious clients, three users, one per role, and
# finished calls of the last days. A second run adds nothing.
class DemoData
  DAYS = 60
  CALLS = 150

  # Public buildings from the State Address Register (data.gov.lv, dataset
  # varis-atvertie-dati, file aw_eka.csv, licence CC BY 4.0, read on
  # 2026-10-02).
  ADDRESSES = [
    [ 101_111_511, "Jaņa Rozentāla laukums 1, Rīga, LV-1010", 56.955767, 24.11308, "2016-12-13" ],
    [ 103_877_933, "Rātslaukums 1, Rīga, LV-1050", 56.947812, 24.106339, "2014-10-06" ],
    [ 101_845_088, "Kronvalda bulvāris 2, Rīga, LV-1010", 56.953635, 24.104873, "2019-08-07" ],
    [ 101_827_246, "Dzirciema iela 16, Rīga, LV-1007", 56.953326, 24.055206, "2024-04-30" ],
    [ 101_950_675, "Meža prospekts 1, Rīga, LV-1014", 57.006749, 24.1601, "2003-01-10" ],
    [ 104_743_600, "Skanstes iela 21, Rīga, LV-1013", 56.96792, 24.121447, "2004-08-12" ],
    [ 101_126_074, "Brīvības iela 75, Rīga, LV-1001", 56.959788, 24.126174, "2025-05-14" ],
    [ 101_956_694, "Nēģu iela 7, Rīga, LV-1050", 56.944002, 24.117344, "2020-08-12" ]
  ].freeze

  # Name, client, type, district and contract start of each site, in the
  # order of the addresses; contracts C-00015 onwards.
  SITES = [
    [ "Demo Office 5", "Example Media Ltd", :office, :centre, "2026-01-12" ],
    [ "Demo Office 6", "Sample Consulting Ltd", :office, :centre, "2026-02-03" ],
    [ "Demo Office 7", "Test Studio Ltd", :office, :centre, "2026-03-16" ],
    [ "Demo Office 8", "Example Health Ltd", :office, :west, "2026-04-01" ],
    [ "Demo Warehouse 9", "Sample Storage Ltd", :warehouse, :north, "2026-04-20" ],
    [ "Demo Shop 10", "Example Events Ltd", :shop, :north, "2026-05-11" ],
    [ "Demo Office 11", "Test Logistics Ltd", :office, :east, "2026-06-01" ],
    [ "Demo Shop 12", "Sample Market Ltd", :shop, :south, "2026-06-22" ]
  ].freeze

  USERS = { "dispatcher" => "Demo Dispatcher", "supervisor" => "Demo Supervisor",
            "administrator" => "Demo Administrator" }.freeze

  Result = Data.define(:sites, :passwords, :calls) do
    def to_s
      return "Demo data is loaded already; nothing added" if [ sites, passwords.size, calls ].all?(&:zero?)

      [ "#{sites} sites, #{passwords.size} users and #{calls} calls added",
        *passwords.map { |email, password| "#{email} #{password}" } ].join("\n")
    end
  end

  def initialize(random: Random.new(2026))
    @random = random
  end

  # The open boards learn of new calls after the commit, so the suppression
  # wraps the transaction; Turbo keeps its flag per class, hence both kinds.
  def call
    AlarmCall.suppressing_turbo_broadcasts do
      ClientCall.suppressing_turbo_broadcasts do
        Call.transaction { Result.new(sites: add_sites, passwords: add_users, calls: add_calls) }
      end
    end
  end

  private

  def add_sites
    ADDRESSES.zip(SITES).each_with_index.count do |((code, full_address, latitude, longitude, updated), site), index|
      number = format("C-%05d", 15 + index)
      next false if GuardedSite.exists?(contract_number: number)

      address = Address.find_or_create_by!(code:) do |found|
        found.assign_attributes(full_address:, postal_code: full_address[/LV-\d{4}/], latitude:, longitude:,
                                register_updated_on: updated)
      end
      create_site(number, address, *site)
    end
  end

  def create_site(number, address, name, client, type, district, start)
    GuardedSite.create!(contract_number: number, name:, client_name: client, address:, site_type: type, district:,
                        keyholder_phone: "+37100000#{number[-3..]}", contract_start_date: start)
  end

  def add_users
    USERS.each_with_object({}) do |(role, name), passwords|
      email = "#{role}@example.com"
      next if User.exists?(email_address: email)

      password = SecureRandom.alphanumeric(20)
      User.create!(email_address: email, name:, role:, password:)
      passwords[email] = password
    end
  end

  def add_calls
    dispatcher, supervisor = %w[ dispatcher supervisor ].map { |role| User.find_by!(email_address: "#{role}@example.com") }
    return 0 if Call.exists?(registered_by: dispatcher)

    calls = DemoCalls.new(random: @random, sites: GuardedSite.active.to_a, cars: PatrolCar.where.not(status: :out_of_service).to_a,
                          people: [ dispatcher, supervisor ])
    CALLS.times { calls.add(Time.current - calls.age(DAYS)) }
    CALLS
  end
end
