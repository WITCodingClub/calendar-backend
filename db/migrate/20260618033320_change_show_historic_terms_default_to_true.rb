class ChangeShowHistoricTermsDefaultToTrue < ActiveRecord::Migration[8.1]
  def change
    change_column_default :user_extension_configs, :show_historic_terms, from: false, to: true
  end
end
