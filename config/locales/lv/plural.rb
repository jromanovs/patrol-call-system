# USR-10: how Latvian counts. After 0, after 10 to 20 and after the tens the
# thing counted stands in the genitive ("12 izsaukumu"), after 1, 21, 31 … in
# the singular, after the rest in the plural. The rule of the gem rails-i18n
# has the last two forms only, so the first would never be shown.
{
  lv: {
    i18n: {
      plural: {
        keys: %i[ zero one other ],
        rule: lambda do |count|
          next :other unless count.is_a?(Numeric) && count.to_i == count
          next :zero if (count % 10).zero? || (11..19).cover?(count % 100)

          count % 10 == 1 ? :one : :other
        end
      }
    }
  }
}
