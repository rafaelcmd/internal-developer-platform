(ns cost-manager.domain.value-objects.money)

(defrecord Money [amount currency])

(defn make-money
  "Creates a Money value object. Amounts may be zero or negative
   (credits, refunds, adjustments). Currency is required."
  [amount currency]
  {:pre [(number? amount)
         (string? currency)
         (not (empty? currency))]}
  (->Money (bigdec amount) currency))
