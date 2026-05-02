(ns cost-manager.domain.value-objects.money-test
  (:require [clojure.test :refer [deftest is testing]]
            [cost-manager.domain.value-objects.money :refer [make-money]])
  (:import [cost_manager.domain.value_objects.money Money]))

(deftest test-make-money

  (testing "creates a Money record with valid inputs"
    (let [money (make-money 100 "USD")]
      (is (instance? Money money))
      (is (= (bigdec 100) (:amount money)))
      (is (= "USD" (:currency money)))))

  (testing "coerces amount to BigDecimal"
    (is (instance? BigDecimal (:amount (make-money 150.25 "USD"))))
    (is (instance? BigDecimal (:amount (make-money 100 "USD")))))

  (testing "accepts zero amount (free-tier usage)"
    (is (= (bigdec 0) (:amount (make-money 0 "USD")))))

  (testing "accepts negative amount (credits, refunds)"
    (is (= (bigdec -50) (:amount (make-money -50 "USD")))))

  (testing "rejects non-number amount"
    (is (thrown? AssertionError (make-money "100" "USD"))))

  (testing "rejects non-string currency"
    (is (thrown? AssertionError (make-money 100 123))))

  (testing "rejects empty currency"
    (is (thrown? AssertionError (make-money 100 "")))))
