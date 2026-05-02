(ns cost-manager.domain.entities.cost-record-test
  (:require [clojure.test :refer [deftest is testing]]
            [cost-manager.domain.entities.cost-record :refer [make-cost-record]]
            [cost-manager.domain.value-objects.time-interval :refer [make-time-interval]]
            [cost-manager.domain.value-objects.service :refer [make-service]]
            [cost-manager.domain.value-objects.usage :refer [make-usage]])
  (:import [cost_manager.domain.entities.cost_record CostRecord]))

(def ^:private test-interval
  (make-time-interval #inst "2026-03-01" #inst "2026-03-02" :daily))

(def ^:private test-service
  (make-service "AmazonEC2" :compute))

(defn- valid-cost-record-params []
  {:id          "cr-1"
   :resource-id "res-1"
   :interval    test-interval
   :amount      150.0
   :currency    "USD"
   :charge-type :usage
   :service     test-service
   :source      :aws-cost-explorer})

(deftest make-cost-record-test

  (testing "creates a CostRecord with valid inputs"
    (let [record (make-cost-record (valid-cost-record-params))]
      (is (instance? CostRecord record))
      (is (= "cr-1" (:id record)))
      (is (= "res-1" (:resource-id record)))
      (is (= test-interval (:interval record)))
      (is (= (bigdec 150.0) (get-in record [:amount :amount])))
      (is (= "USD" (get-in record [:amount :currency])))
      (is (nil? (:amortized-amount record)))
      (is (nil? (:usage record)))
      (is (= :usage (:charge-type record)))
      (is (= test-service (:service record)))
      (is (= :aws-cost-explorer (:source record)))))

  (testing "accepts a negative amount for credits"
    (let [record (make-cost-record
                  (assoc (valid-cost-record-params)
                         :amount -10.0
                         :charge-type :credit))]
      (is (= (bigdec -10.0) (get-in record [:amount :amount])))))

  (testing "accepts a zero amount"
    (let [record (make-cost-record (assoc (valid-cost-record-params) :amount 0))]
      (is (= (bigdec 0) (get-in record [:amount :amount])))))

  (testing "accepts an amortized amount when currency is also provided"
    (let [record (make-cost-record
                  (assoc (valid-cost-record-params)
                         :amortized-amount 120.0
                         :amortized-currency "USD"))]
      (is (= (bigdec 120.0) (get-in record [:amortized-amount :amount])))))

  (testing "accepts a usage value object"
    (let [record (make-cost-record
                  (assoc (valid-cost-record-params)
                         :usage (make-usage 24 "hours")))]
      (is (= 24 (get-in record [:usage :quantity])))
      (is (= "hours" (get-in record [:usage :unit])))))

  (testing "rejects an unknown charge-type"
    (is (thrown? AssertionError
                 (make-cost-record
                  (assoc (valid-cost-record-params) :charge-type :mystery)))))

  (testing "rejects an unknown source"
    (is (thrown? AssertionError
                 (make-cost-record
                  (assoc (valid-cost-record-params) :source :oracle-billing)))))

  (testing "rejects a missing interval"
    (is (thrown? AssertionError
                 (make-cost-record
                  (dissoc (valid-cost-record-params) :interval)))))

  (testing "rejects amortized-amount without amortized-currency"
    (is (thrown? AssertionError
                 (make-cost-record
                  (assoc (valid-cost-record-params)
                         :amortized-amount 120.0))))))
