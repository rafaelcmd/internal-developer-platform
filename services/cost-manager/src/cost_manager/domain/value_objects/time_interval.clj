(ns cost-manager.domain.value-objects.time-interval)

(def valid-granularities #{:hourly :daily :monthly})

(defrecord TimeInterval [start end granularity])

(defn make-time-interval
  "Creates a TimeInterval. `start` and `end` must be inst? values;
   `end` must be greater than or equal to `start`."
  [start end granularity]
  {:pre [(inst? start)
         (inst? end)
         (<= (inst-ms start) (inst-ms end))
         (contains? valid-granularities granularity)]}
  (->TimeInterval start end granularity))
