# A call made by the client by phone (2.6).
class ClientCall < Call
  validates :caller_name, presence: true, length: { in: 2..100 }
  validates :caller_phone, format: { with: /\A\+\d{8,15}\z/ }

  # BR-2: a client call starts as normal; the dispatcher may change it.
  before_validation { self.priority = "normal" if priority.blank? }

  def summary = I18n.t("models.client_call.summary")

  def detail = "#{caller_name}, #{caller_phone}"
end
