(ns cost-manager.domain.aggregates.resource-cost-test
  (:require [clojure.test :refer [deftest is testing]]
            [cost-manager.domain.aggregates.resource-cost
             :refer [make-resource-cost add-cost-record total-cost]]
            [cost-manager.domain.entities.cloud-resource :refer [make-cloud-resource]]
            [cost-manager.domain.entities.cost-record :refer [make-cost-record]]
            [cost-manager.domain.value-objects.account :refer [make-account]]
            [cost-manager.domain.value-objects.service :refer [make-service]]
            [cost-manager.domain.value-objects.time-interval :refer [make-time-interval]]))

(def ^:private test-account
  (make-account :aws "123456789012" "platform-prod"))

(def ^:private test-resource
  (make-cloud-resource
   {:id                   "res-1"
    :provider-resource-id "arn:aws:ec2:us-east-1:123456789012:instance/i-abc"
    :name                 "my-ec2"
    :provider-type        "t3.micro"
    :category             :compute
    :provider             :aws
    :region               "us-east-1"
    :account              test-account
    :tags                 {}
    :created-at           #inst "2026-03-01"}))

(def ^:private test-interval
  (make-time-interval #inst "2026-03-01" #inst "2026-03-02" :daily))

(def ^:private test-service
  (make-service "AmazonEC2" :compute))

(defn- cost-record [id amount & {:keys [currency charge-type amortized-amount]
                                 :or   {currency "USD" charge-type :usage}}]
  (make-cost-record
   (cond-> {:id          id
            :resource-id "res-1"
            :interval    test-interval
            :amount      amount
            :currency    currency
            :charge-type charge-type
            :service     test-service
            :source      :aws-cost-explorer}
     amortized-amount (assoc :amortized-amount amortized-amount
                             :amortized-currency currency))))

(deftest make-resource-cost-test

  (testing "creates a ResourceCost aggregate with empty cost records"
    (let [aggregate (make-resource-cost test-resource)]
      (is (= test-resource (:resource aggregate)))
      (is (empty? (:cost-records aggregate))))))

(deftest add-cost-record-test

  (testing "adds a cost record to the aggregate"
    (let [aggregate (-> (make-resource-cost test-resource)
                        (add-cost-record (cost-record "cr-1" 100.0)))]
      (is (= 1 (count (:cost-records aggregate)))))))

(deftest total-cost-test

  (testing "sums usage cost records"
    (let [aggregate (-> (make-resource-cost test-resource)
                        (add-cost-record (cost-record "cr-1" 100.0))
                        (add-cost-record (cost-record "cr-2" 50.0)))]
      (is (= (bigdec 150.0) (total-cost aggregate)))))

  (testing "returns zero when there are no cost records"
    (is (= (bigdec 0) (total-cost (make-resource-cost test-resource)))))

  (testing "includes credits by default (netting them out)"
    (let [aggregate (-> (make-resource-cost test-resource)
                        (add-cost-record (cost-record "cr-1" 100.0))
                        (add-cost-record (cost-record "cr-2" -20.0
                                                      :charge-type :credit)))]
      (is (= (bigdec 80.0) (total-cost aggregate)))))

  (testing "can exclude credits via option"
    (let [aggregate (-> (make-resource-cost test-resource)
                        (add-cost-record (cost-record "cr-1" 100.0))
                        (add-cost-record (cost-record "cr-2" -20.0
                                                      :charge-type :credit)))]
      (is (= (bigdec 100.0)
             (total-cost aggregate {:include-credits? false})))))

  (testing "uses amortized-amount when cost-type is :amortized"
    (let [aggregate (-> (make-resource-cost test-resource)
                        (add-cost-record (cost-record "cr-1" 100.0
                                                      :amortized-amount 70.0)))]
      (is (= (bigdec 100.0) (total-cost aggregate)))
      (is (= (bigdec 70.0) (total-cost aggregate {:cost-type :amortized})))))

  (testing "amortized falls back to amount when no amortized-amount present"
    (let [aggregate (-> (make-resource-cost test-resource)
                        (add-cost-record (cost-record "cr-1" 100.0)))]
      (is (= (bigdec 100.0) (total-cost aggregate {:cost-type :amortized})))))

  (testing "throws when records carry mixed currencies"
    (let [aggregate (-> (make-resource-cost test-resource)
                        (add-cost-record (cost-record "cr-1" 100.0 :currency "USD"))
                        (add-cost-record (cost-record "cr-2" 50.0 :currency "EUR")))]
      (is (thrown? clojure.lang.ExceptionInfo (total-cost aggregate))))))
