(ns cost-manager.domain.value-objects.usage)

(defrecord Usage [quantity unit])

(defn make-usage
  "Creates a Usage value object. `unit` is a normalized string such as
   \"hours\", \"gb-month\", \"requests\"."
  [quantity unit]
  {:pre [(number? quantity)
         (not (neg? quantity))
         (string? unit)
         (not (empty? unit))]}
  (->Usage quantity unit))
