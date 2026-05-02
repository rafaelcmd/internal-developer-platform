(ns cost-manager.domain.entities.cloud-resource
  (:require [cost-manager.domain.value-objects.cloud-provider :refer [make-cloud-provider]]
            [cost-manager.domain.value-objects.resource-type :refer [make-resource-type]]))

(defrecord CloudResource
  [id
   provider-resource-id
   name
   type
   provider
   region
   account
   tags
   created-at
   terminated-at])

(defn make-cloud-resource
  "Creates a CloudResource from a map of fields. Required keys:
     :id, :provider-resource-id, :name, :provider-type, :category,
     :provider, :region, :account, :created-at.
   Optional keys: :tags (default {}), :terminated-at (nilable)."
  [{:keys [id
           provider-resource-id
           name
           provider-type
           category
           provider
           region
           account
           tags
           created-at
           terminated-at]
    :or   {tags {}}}]
  {:pre [(string? id) (not (empty? id))
         (string? provider-resource-id) (not (empty? provider-resource-id))
         (string? name) (not (empty? name))
         (string? region) (not (empty? region))
         (some? account)
         (map? tags)
         (inst? created-at)
         (or (nil? terminated-at) (inst? terminated-at))]}
  (->CloudResource id
                   provider-resource-id
                   name
                   (make-resource-type provider-type category)
                   (make-cloud-provider provider)
                   region
                   account
                   tags
                   created-at
                   terminated-at))
