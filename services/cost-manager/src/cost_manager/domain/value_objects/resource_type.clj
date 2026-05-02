(ns cost-manager.domain.value-objects.resource-type)

(def valid-categories #{:compute :storage :database :network :other})

(defrecord ResourceType [provider-type category])

(defn make-resource-type
  "Creates a ResourceType. `provider-type` is the raw string from the
   provider (e.g. \"t3.micro\", \"n1-standard-1\", \"Standard_D2s_v3\").
   `category` is the normalized category keyword used for cross-provider
   reporting."
  [provider-type category]
  {:pre [(string? provider-type)
         (not (empty? provider-type))
         (contains? valid-categories category)]}
  (->ResourceType provider-type category))
