require "open3"

# Scripts of the page run by Node: what the page gives a script, as the
# example makes it up, then the scripts' own text, then the lines of the
# example, which read what the example sends as `sent` and print their answer
# as JSON. The text is given whole, so Node is not left to decide from a
# file's name whether it is a module.
module NodeScript
  READ = <<~JS.freeze
    let text = ""
    for await (const part of process.stdin) text += part
    const sent = JSON.parse(text)
  JS

  def node(sources, lines, sent, page: "")
    script = [ page, "class Controller {}", *Array(sources).map { |source| page_script(source) }, READ, lines ].join("\n")
    printed, said, result = Open3.capture3("node", "--input-type=module", "-e", script, stdin_data: sent.to_json)
    raise said unless result.success?

    JSON.parse(printed)
  end

  private

  # A script without the lines that fetch other scripts — the example lists
  # those itself, and spec/javascript/fetched_spec.rb holds the lines to what
  # is there — and with its class under the name Subject.
  def page_script(source)
    Rails.root.join("app/javascript", source).read.gsub(/^import .*\n/, "").sub("export default class", "const Subject = class")
  end
end
