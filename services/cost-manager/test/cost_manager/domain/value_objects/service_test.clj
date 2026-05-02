(ns cost-manager.domain.value-objects.service-test
  (:require [clojure.test :refer [deftest is testing]]
            [cost-manager.domain.value-objects.service :refer [make-service]])
  (:import [cost_manager.domain.value_objects.service Service]))

(deftest make-service-test

  (testing "creates a Service with provider name and canonical name"
    (let [service (make-service "AmazonEC2" :compute)]
      (is (instance? Service service))
      (is (= "AmazonEC2" (:provider-name service)))
      (is (= :compute (:canonical-name service)))))

  (testing "rejects an unknown canonical name"
    (is (thrown? AssertionError (make-service "AmazonEC2" :quantum-compute))))

  (testing "rejects an empty provider name"
    (is (thrown? AssertionError (make-service "" :compute)))))
