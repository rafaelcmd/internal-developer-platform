(ns cost-manager.domain.value-objects.account-test
  (:require [clojure.test :refer [deftest is testing]]
            [cost-manager.domain.value-objects.account :refer [make-account]])
  (:import [cost_manager.domain.value_objects.account Account]))

(deftest make-account-test

  (testing "creates an Account with provider, id, and name"
    (let [account (make-account :aws "123456789012" "platform-prod")]
      (is (instance? Account account))
      (is (= :aws (get-in account [:provider :name])))
      (is (= "123456789012" (:id account)))
      (is (= "platform-prod" (:name account)))))

  (testing "accepts nil name"
    (is (instance? Account (make-account :gcp "my-project" nil))))

  (testing "rejects an unknown provider"
    (is (thrown? AssertionError (make-account :digitalocean "abc" "x"))))

  (testing "rejects an empty id"
    (is (thrown? AssertionError (make-account :aws "" "x")))))
