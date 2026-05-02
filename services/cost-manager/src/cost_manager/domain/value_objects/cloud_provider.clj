(ns cost-manager.domain.value-objects.cloud-provider)

(def valid-providers #{:aws :gcp :azure})

(defrecord CloudProvider [name])

(defn make-cloud-provider [name]
  {:pre [(contains? valid-providers name)]}
  (->CloudProvider name))
