# CRW-10, BR-19: a photo the crew took on site of a call, its file kept by
# Active Storage; its time is when it reached the server.
class CallPhoto < ApplicationRecord
  include KindByContent

  EXTENSIONS = { "image/jpeg" => ".jpg", "image/png" => ".png", "image/webp" => ".webp" }.freeze
  TYPES = EXTENSIONS.keys.freeze
  LIMIT = 5.megabytes

  belongs_to :call
  belongs_to :user
  has_one_attached :image

  validate :photo_image

  # Why a file is refused as a photo, also one too large to be read.
  def self.refusal = I18n.t("activerecord.errors.models.call_photo.not_a_photo")

  # The name a photo is sent under ends as its checked kind, whatever the
  # phone called it.
  def extension = EXTENSIONS.fetch(image.content_type)

  private

  def photo_image
    errors.add(:base, :not_a_photo) unless image.attached? && image.byte_size <= LIMIT && kind_of(:image).in?(TYPES)
  end
end
