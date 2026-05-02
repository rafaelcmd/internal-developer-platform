(ns cost-manager.domain.value-objects.resource-type-test
  (:require [clojure.test :refer [deftest is testing]]
            [cost-manager.domain.value-objects.resource-type :refer [make-resource-type]])
  (:import [cost_manager.domain.value_objects.resource_type ResourceType]))

(deftest make-resource-type-test

  (testing "creates a ResourceType with a provider-type and category"
    (let [resource-type (make-resource-type "t3.micro" :compute)]
      (is (instance? ResourceType resource-type))
      (is (= "t3.micro" (:provider-type resource-type)))
      (is (= :compute (:category resource-type)))))

  (testing "accepts all valid categories"
    (doseq [cat [:compute :storage :database :network :other]]
      (is (instance? ResourceType (make-resource-type "x" cat)))))

  (testing "rejects an unknown category"
    (is (thrown? AssertionError (make-resource-type "t3.micro" :quantum))))

  (testing "rejects an empty provider-type"
    (is (thrown? AssertionError (make-resource-type "" :compute))))

  (testing "rejects a non-string provider-type"
    (is (thrown? AssertionError (make-resource-type 123 :compute)))))
