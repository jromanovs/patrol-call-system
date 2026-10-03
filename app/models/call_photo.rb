# CRW-10, BR-19: a photo the crew took on site of a call, its file kept by
# Active Storage; its time is when it reached the server.
class CallPhoto < ApplicationRecord
  TYPES = %w[ image/jpeg image/png image/webp ].freeze
  LIMIT = 5.megabytes
  REFUSAL = "Photo must be a JPEG, PNG or WebP image of at most 5 MB".freeze

  belongs_to :call
  belongs_to :user
  has_one_attached :image

  validate :photo_image

  private

  def photo_image
    errors.add(:base, REFUSAL) unless image.attached? && image.byte_size <= LIMIT && kind.in?(TYPES)
  end

  # The kind of file its own first bytes show: neither its name nor the
  # browser's word for it counts.
  def kind
    change = attachment_changes["image"]
    return image.content_type unless change

    io = change.attachable.is_a?(Hash) ? change.attachable[:io] : change.attachable
    io = io.tempfile if io.respond_to?(:tempfile)
    Marcel::Magic.by_magic(io)&.type.tap { io.rewind }
  end
end
