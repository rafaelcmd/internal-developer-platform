(ns cost-manager.domain.value-objects.account
  (:require [cost-manager.domain.value-objects.cloud-provider :refer [make-cloud-provider]]))

(defrecord Account [provider id name])

(defn make-account
  "Creates an Account. Wraps AWS account / GCP project / Azure subscription
   behind a single concept. `id` is the provider's identifier; `name` is
   the human-readable label (nilable)."
  [provider id name]
  {:pre [(string? id)
         (not (empty? id))
         (or (nil? name) (string? name))]}
  (->Account (make-cloud-provider provider) id name))
