(ns cost-manager.domain.aggregates.resource-cost)

(def ^:private cost-affecting-charge-types
  #{:usage :tax :commitment-fee :adjustment})

(def ^:private credit-charge-types
  #{:credit :refund :discount})

(defrecord ResourceCost [resource cost-records])

(defn make-resource-cost [resource]
  (->ResourceCost resource []))

(defn add-cost-record [aggregate cost-record]
  (update aggregate :cost-records conj cost-record))

(defn- relevant-record? [{:keys [charge-type]} include-credits?]
  (or (contains? cost-affecting-charge-types charge-type)
      (and include-credits? (contains? credit-charge-types charge-type))))

(defn- record-money [record cost-type]
  (if (and (= cost-type :amortized) (:amortized-amount record))
    (:amortized-amount record)
    (:amount record)))

(defn total-cost
  "Sums cost records in the aggregate.

   Options map:
     :cost-type        :default | :amortized  (default :default).
                       :amortized falls back to :amount when no
                       amortized-amount is present on a record.
     :include-credits? whether to include credits/refunds/discounts
                       (default true).

   Throws ex-info if records carry mixed currencies."
  ([aggregate] (total-cost aggregate {}))
  ([aggregate {:keys [cost-type include-credits?]
               :or   {cost-type :default include-credits? true}}]
   (let [relevant   (filter #(relevant-record? % include-credits?)
                            (:cost-records aggregate))
         monies     (map #(record-money % cost-type) relevant)
         currencies (into #{} (map :currency monies))]
     (cond
       (empty? monies)
       (bigdec 0)

       (> (count currencies) 1)
       (throw (ex-info "Cannot sum cost records with mixed currencies"
                       {:currencies currencies}))

       :else
       (reduce + (bigdec 0) (map :amount monies))))))
