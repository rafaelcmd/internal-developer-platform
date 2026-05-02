(ns cost-manager.domain.entities.cloud-resource-test
  (:require [clojure.test :refer [deftest is testing]]
            [cost-manager.domain.entities.cloud-resource :refer [make-cloud-resource]]
            [cost-manager.domain.value-objects.account :refer [make-account]])
  (:import [cost_manager.domain.entities.cloud_resource CloudResource]))

(def ^:private test-account
  (make-account :aws "123456789012" "platform-prod"))

(defn- valid-resource-params []
  {:id                   "res-1"
   :provider-resource-id "arn:aws:ec2:us-east-1:123456789012:instance/i-abc"
   :name                 "my-ec2"
   :provider-type        "t3.micro"
   :category             :compute
   :provider             :aws
   :region               "us-east-1"
   :account              test-account
   :tags                 {"team" "platform" "env" "prod"}
   :created-at           #inst "2026-03-01"})

(deftest make-cloud-resource-test

  (testing "creates a CloudResource with valid inputs"
    (let [resource (make-cloud-resource (valid-resource-params))]
      (is (instance? CloudResource resource))
      (is (= "res-1" (:id resource)))
      (is (= "arn:aws:ec2:us-east-1:123456789012:instance/i-abc"
             (:provider-resource-id resource)))
      (is (= "my-ec2" (:name resource)))
      (is (= "t3.micro" (get-in resource [:type :provider-type])))
      (is (= :compute (get-in resource [:type :category])))
      (is (= :aws (get-in resource [:provider :name])))
      (is (= "us-east-1" (:region resource)))
      (is (= test-account (:account resource)))
      (is (= {"team" "platform" "env" "prod"} (:tags resource)))
      (is (= #inst "2026-03-01" (:created-at resource)))
      (is (nil? (:terminated-at resource)))))

  (testing "accepts a terminated-at timestamp"
    (let [resource (make-cloud-resource
                    (assoc (valid-resource-params)
                           :terminated-at #inst "2026-04-01"))]
      (is (= #inst "2026-04-01" (:terminated-at resource)))))

  (testing "defaults tags to an empty map"
    (let [resource (make-cloud-resource
                    (dissoc (valid-resource-params) :tags))]
      (is (= {} (:tags resource)))))

  (testing "rejects an invalid cloud provider"
    (is (thrown? AssertionError
                 (make-cloud-resource
                  (assoc (valid-resource-params) :provider :digitalocean)))))

  (testing "rejects an invalid category"
    (is (thrown? AssertionError
                 (make-cloud-resource
                  (assoc (valid-resource-params) :category :quantum)))))

  (testing "rejects an empty name"
    (is (thrown? AssertionError
                 (make-cloud-resource
                  (assoc (valid-resource-params) :name "")))))

  (testing "rejects a missing provider-resource-id"
    (is (thrown? AssertionError
                 (make-cloud-resource
                  (assoc (valid-resource-params) :provider-resource-id "")))))

  (testing "rejects a missing created-at"
    (is (thrown? AssertionError
                 (make-cloud-resource
                  (dissoc (valid-resource-params) :created-at))))))
