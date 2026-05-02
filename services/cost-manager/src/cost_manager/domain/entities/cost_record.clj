(ns cost-manager.domain.entities.cost-record
  (:require [cost-manager.domain.value-objects.money :refer [make-money]]))

(def valid-charge-types
  #{:usage :tax :credit :refund :commitment-fee :discount :adjustment})

(def valid-sources
  #{:aws-cost-explorer :aws-cur :gcp-billing :azure-cost-mgmt})

(defrecord CostRecord
  [id
   resource-id
   interval
   amount
   amortized-amount
   usage
   charge-type
   service
   source])

(defn make-cost-record
  "Creates a CostRecord from a map of fields. Required keys:
     :id, :resource-id, :interval, :amount, :currency,
     :charge-type, :service, :source.
   Optional keys:
     :amortized-amount + :amortized-currency (both or neither),
     :usage (a Usage value object)."
  [{:keys [id
           resource-id
           interval
           amount
           currency
           amortized-amount
           amortized-currency
           usage
           charge-type
           service
           source]}]
  {:pre [(string? id) (not (empty? id))
         (string? resource-id) (not (empty? resource-id))
         (some? interval)
         (number? amount)
         (contains? valid-charge-types charge-type)
         (some? service)
         (contains? valid-sources source)
         (or (and (nil? amortized-amount) (nil? amortized-currency))
             (and (number? amortized-amount) (string? amortized-currency)))]}
  (->CostRecord id
                resource-id
                interval
                (make-money amount currency)
                (when (some? amortized-amount)
                  (make-money amortized-amount amortized-currency))
                usage
                charge-type
                service
                source))
