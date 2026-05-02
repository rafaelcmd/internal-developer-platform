(ns cost-manager.domain.value-objects.usage-test
  (:require [clojure.test :refer [deftest is testing]]
            [cost-manager.domain.value-objects.usage :refer [make-usage]])
  (:import [cost_manager.domain.value_objects.usage Usage]))

(deftest make-usage-test

  (testing "creates a Usage with quantity and unit"
    (let [usage (make-usage 24 "hours")]
      (is (instance? Usage usage))
      (is (= 24 (:quantity usage)))
      (is (= "hours" (:unit usage)))))

  (testing "accepts zero quantity"
    (is (instance? Usage (make-usage 0 "hours"))))

  (testing "rejects negative quantity"
    (is (thrown? AssertionError (make-usage -1 "hours"))))

  (testing "rejects empty unit"
    (is (thrown? AssertionError (make-usage 24 ""))))

  (testing "rejects non-number quantity"
    (is (thrown? AssertionError (make-usage "24" "hours")))))
