require "open3"

# A module of the page run by Node: the module's own text, then the lines of
# the example, which read what the example sends as `sent` and print their
# answer as JSON. The text is given whole, so Node is not left to decide from
# the file's name whether it is a module.
module NodeScript
  READ = <<~JS.freeze
    let text = ""
    for await (const part of process.stdin) text += part
    const sent = JSON.parse(text)
  JS

  def node(source, lines, sent)
    script = [ Rails.root.join("app/javascript", source).read, READ, lines ].join("\n")
    printed, said, result = Open3.capture3("node", "--input-type=module", "-e", script, stdin_data: sent.to_json)
    raise said unless result.success?

    JSON.parse(printed)
  end
end
