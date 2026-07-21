class CreateEmbeddings < ActiveRecord::Migration[8.1]
  def change
    create_table :embeddings do |t|
      t.references :album, null: false, foreign_key: true, index: { unique: true }
      t.vector :sonic, limit: 1536
      t.vector :emotional, limit: 1536
      t.vector :situational, limit: 1536
      t.vector :era, limit: 1536

      t.timestamps
    end
  end
end
