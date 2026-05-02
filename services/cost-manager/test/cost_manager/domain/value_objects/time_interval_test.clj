(ns cost-manager.domain.value-objects.time-interval-test
  (:require [clojure.test :refer [deftest is testing]]
            [cost-manager.domain.value-objects.time-interval :refer [make-time-interval]])
  (:import [cost_manager.domain.value_objects.time_interval TimeInterval]))

(deftest make-time-interval-test

  (testing "creates a TimeInterval with valid inputs"
    (let [interval (make-time-interval #inst "2026-03-01" #inst "2026-03-02" :daily)]
      (is (instance? TimeInterval interval))
      (is (= :daily (:granularity interval)))))

  (testing "accepts all valid granularities"
    (doseq [g [:hourly :daily :monthly]]
      (is (instance? TimeInterval
                     (make-time-interval #inst "2026-03-01" #inst "2026-03-02" g)))))

  (testing "accepts equal start and end (zero-duration interval)"
    (is (instance? TimeInterval
                   (make-time-interval #inst "2026-03-01" #inst "2026-03-01" :daily))))

  (testing "rejects end before start"
    (is (thrown? AssertionError
                 (make-time-interval #inst "2026-03-02" #inst "2026-03-01" :daily))))

  (testing "rejects an unknown granularity"
    (is (thrown? AssertionError
                 (make-time-interval #inst "2026-03-01" #inst "2026-03-02" :yearly))))

  (testing "rejects non-inst values"
    (is (thrown? AssertionError (make-time-interval "2026-03-01" #inst "2026-03-02" :daily)))))
