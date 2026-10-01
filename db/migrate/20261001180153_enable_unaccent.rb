# FLT-07: address search regardless of Latvian diacritics (brivibas finds
# Brīvības). unaccent ships with PostgreSQL and is a trusted extension.
class EnableUnaccent < ActiveRecord::Migration[8.1]
  def change
    enable_extension "unaccent"
  end
end
