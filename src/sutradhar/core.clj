(ns sutradhar.core
  "CLI entry point for the sūtradhār pipeline."
  (:require [sutradhar.reader :as reader]
            [sutradhar.proposer :as proposer]
            [clojure.java.io :as io]))

(defn- resolve-paths
  "Resolve default paths relative to the sutradhar directory."
  []
  (let [sutradhar-dir (System/getProperty "user.dir")
        root          (-> (io/file sutradhar-dir) .getParentFile)]
    {:sutra-relay (str (io/file root ".." "sutra" "relay"))
     :data-cljs   (str (io/file root "website" "project-constellation"
                                "src" "project_constellation" "data.cljs"))
     :mayalucia-root (str root)}))

(defn run
  "Run the sūtradhār pipeline: read → propose → report."
  [{:keys [sutra-relay data-cljs]}]
  (let [messages   (reader/read-relay sutra-relay)
        entity-ids (proposer/extract-entity-ids data-cljs)
        edge-pairs (proposer/extract-edge-pairs data-cljs)
        report     (proposer/generate-report
                     {:messages   messages
                      :entity-ids entity-ids
                      :edge-pairs edge-pairs})]
    (println (proposer/format-report report))
    report))

(defn -main [& args]
  (let [paths (resolve-paths)
        sutra (or (first args) (:sutra-relay paths))
        data  (or (second args) (:data-cljs paths))]
    (if (and (.isDirectory (io/file sutra))
             (.isFile (io/file data)))
      (run {:sutra-relay sutra :data-cljs data})
      (do
        (println "Usage: clj -M:run [sutra-relay-dir] [data.cljs-path]")
        (println "")
        (println "Defaults:")
        (println "  sutra: " (:sutra-relay paths))
        (println "  data:  " (:data-cljs paths))
        (System/exit 1)))))
