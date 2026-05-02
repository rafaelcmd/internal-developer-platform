(ns cost-manager.domain.value-objects.service)

(def valid-canonical-names
  #{:compute :object-storage :block-storage :managed-database
    :network :data-transfer :other})

(defrecord Service [provider-name canonical-name])

(defn make-service
  "Creates a Service. `provider-name` is the vendor's name for the
   service (e.g. \"AmazonEC2\", \"Compute Engine\", \"Virtual Machines\").
   `canonical-name` is the normalized keyword for cross-provider reporting."
  [provider-name canonical-name]
  {:pre [(string? provider-name)
         (not (empty? provider-name))
         (contains? valid-canonical-names canonical-name)]}
  (->Service provider-name canonical-name))
