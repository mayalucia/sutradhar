(ns sutradhar.reader-test
  (:require [clojure.test :refer [deftest is testing]]
            [sutradhar.reader :as reader]))

(deftest parse-message-test
  (testing "synthetic relay message"
    (let [tmp (java.io.File/createTempFile "relay-test" ".md")]
      (spit tmp (str "---\n"
                     "from: test/model\n"
                     "date: 2026-02-28T12:00:00\n"
                     "tags: [bravli, science]\n"
                     "---\n\n"
                     "# Test Message\n\n"
                     "## What\n\n"
                     "A test.\n"))
      (try
        (let [msg (reader/parse-message tmp)]
          (is (= "test/model" (:from msg)))
          (is (= ["bravli" "science"] (:tags msg)))
          (is (= "Test Message" (:title msg)))
          (is (contains? (:sections msg) "what")))
        (finally
          (.delete tmp))))))

(deftest entity-activity-test
  (testing "tag-to-entity mapping"
    (let [messages [{:tags ["bravli" "inference"] :filename "msg1.md"}
                    {:tags ["writing" "story"] :filename "msg2.md"}]]
      (is (= {"bravli" ["msg1.md" "msg1.md"]
              "thread-mayadevgenz" ["msg1.md"]
              "writing" ["msg2.md" "msg2.md"]}
             (reader/entity-activity messages))))))
