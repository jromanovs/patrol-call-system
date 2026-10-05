# The kind of a file being attached, as its own first bytes show: neither its
# name nor the sender's word for it counts.
module KindByContent
  private

  def kind_of(name)
    change = attachment_changes[name.to_s]
    return public_send(name).content_type unless change

    io = change.attachable.is_a?(Hash) ? change.attachable[:io] : change.attachable
    io = io.tempfile if io.respond_to?(:tempfile)
    Marcel::Magic.by_magic(io)&.type.tap { io.rewind }
  end
end
