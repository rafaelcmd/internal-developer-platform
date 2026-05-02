(ns cost-manager.domain.value-objects.cloud-provider-test
  (:require [clojure.test :refer [deftest is testing]]
            [cost-manager.domain.value-objects.cloud-provider :refer [make-cloud-provider]])
  (:import [cost_manager.domain.value_objects.cloud_provider CloudProvider]))

(deftest make-cloud-provider-test

  (testing "creates a CloudProvider record for a valid provider keyword"
    (let [provider (make-cloud-provider :aws)]
      (is (instance? CloudProvider provider))
      (is (= :aws (:name provider)))))

  (testing "accepts all valid providers"
    (is (instance? CloudProvider (make-cloud-provider :aws)))
    (is (instance? CloudProvider (make-cloud-provider :gcp)))
    (is (instance? CloudProvider (make-cloud-provider :azure))))

  (testing "rejects an unknown provider"
    (is (thrown? AssertionError (make-cloud-provider :digitalocean))))

  (testing "rejects a string provider (keywords only)"
    (is (thrown? AssertionError (make-cloud-provider "AWS"))))

  (testing "rejects a nil provider"
    (is (thrown? AssertionError (make-cloud-provider nil)))))
