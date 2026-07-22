class Embedding < ApplicationRecord
  belongs_to :album

  has_neighbors :sonic
  has_neighbors :emotional
  has_neighbors :situational
  has_neighbors :era
end
