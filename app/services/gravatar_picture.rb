# Asked for by name: whatever else happens to load it may stop doing so.
require "net/http"

# USR-07: the picture Gravatar holds for the user's e-mail address. It is
# asked for only when the user presses the button, and is kept here at once:
# pages show the kept copy and never turn to gravatar.com, so the
# fingerprint of the address leaves the system by the user's own choice and
# not with every page.
class GravatarPicture
  # d=404: no picture drawn by Gravatar in place of a missing one.
  ADDRESS = "https://gravatar.com/avatar/%<fingerprint>s?d=404&s=256".freeze
  # The user waits before the page for the answer.
  WAIT = 5
  SILENCE = [ Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError, Net::ProtocolError,
              Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Zlib::Error ].freeze
  # One request to Gravatar at a time in a server process: presses in several
  # windows at once would otherwise hold all its threads while Gravatar is
  # slow, and the board with them.
  BUSY = Mutex.new

  def initialize(user)
    @user = user
  end

  # :taken; :none when Gravatar says it has no picture for the address, or
  # sent what is none; :silent when it did not answer, or answered anything
  # else: too many requests, an error of its own, another address; :busy
  # when another request to it is still under way.
  def take
    return :busy unless BUSY.try_lock

    begin
      keep(ask)
    ensure
      BUSY.unlock
    end
  end

  private

  def keep(answer)
    return :none if answer.is_a?(Net::HTTPNotFound)
    return :silent unless answer.is_a?(Net::HTTPOK)

    picture = { io: StringIO.new(answer.body), filename: "gravatar", content_type: answer.content_type }
    @user.update(avatar: picture) ? :taken : :none
  end

  # Gravatar knows an address by the SHA-256 of it, trimmed and in small
  # letters, which is how the user's address is kept.
  def address = URI(format(ADDRESS, fingerprint: Digest::SHA256.hexdigest(@user.email_address)))

  def ask
    Net::HTTP.start(address.host, address.port, use_ssl: true, open_timeout: WAIT, read_timeout: WAIT) do |http|
      http.get(address.request_uri)
    end
  rescue *SILENCE => error
    Rails.logger.warn("Gravatar did not answer for user #{@user.id}: #{error.class}")
    nil
  end
end
