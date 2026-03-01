(ns sutradhar.proposer
  "Compare discovered state against constellation data.
   Produce proposals for what to add, update, or flag."
  (:require [clojure.java.io :as io]
            [clojure.string :as str]
            [clojure.set :as set]
            [sutradhar.reader :as reader]))

;; === data.cljs extraction ====================================================

(defn extract-entity-ids
  "Extract all :id values from a data.cljs file."
  [data-cljs-path]
  (let [text (slurp data-cljs-path)]
    (set (map second (re-seq #":id\s+\"([^\"]+)\"" text)))))

(defn extract-edge-pairs
  "Extract all (source, target) pairs from edges in data.cljs."
  [data-cljs-path]
  (let [text (slurp data-cljs-path)]
    (set (map (fn [[_ s t]] [s t])
              (re-seq #":source\s+\"([^\"]+)\"\s+:target\s+\"([^\"]+)\"" text)))))

;; === Proposal generation =====================================================

(def structural-ids
  "Entity IDs that are structural (phases, diamond) — always present,
   don't flag as 'quiet' if they have no relay activity."
  #{"measure" "model" "manifest" "evaluate" "diamond-center"})

(def child-prefixes
  "Prefixes for child entities — exclude from quiet-entity analysis."
  #{"pt-" "mp-" "mj-" "bv-" "pa-" "wr-"})

(defn- child-entity? [id]
  (some #(str/starts-with? id %) child-prefixes))

(defn generate-report
  "Generate a proposal report comparing relay state against constellation."
  [{:keys [messages entity-ids edge-pairs]}]
  (let [activity   (reader/entity-activity messages)
        tag-counts (reduce (fn [acc msg]
                             (reduce #(update %1 %2 (fnil inc 0))
                                     acc (:tags msg)))
                           {} messages)
        ;; Entities referenced by relay but not in constellation
        all-mapped (set (mapcat #(get reader/tag->entities % [])
                                (keys tag-counts)))
        missing    (set/difference all-mapped entity-ids)

        ;; Entities in constellation with no relay activity
        quiet      (->> entity-ids
                        (remove structural-ids)
                        (remove child-entity?)
                        (remove activity)
                        sort
                        vec)

        ;; Unmapped tags
        unmapped   (->> (keys tag-counts)
                        (remove reader/tag->entities)
                        sort
                        vec)]

    {:summary {:message-count  (count messages)
               :entity-count   (count entity-ids)
               :edge-count     (count edge-pairs)
               :active-count   (count activity)
               :quiet-count    (count quiet)
               :missing-count  (count missing)
               :unmapped-count (count unmapped)}

     :missing-entities (vec (sort missing))

     :quiet-entities quiet

     :active-entities (->> activity
                           (sort-by (comp - count val))
                           (mapv (fn [[eid files]]
                                   {:id eid
                                    :mentions (count files)
                                    :new? (not (contains? entity-ids eid))})))

     :unmapped-tags (->> unmapped
                         (mapv (fn [tag]
                                 {:tag tag
                                  :count (get tag-counts tag 0)})))}))

(defn format-report
  "Format a proposal report as a human-readable string."
  [{:keys [summary missing-entities quiet-entities
           active-entities unmapped-tags]}]
  (let [lines (transient [])]
    (conj! lines "# Sūtradhār Report")
    (conj! lines "")
    (conj! lines (str "Relay messages: " (:message-count summary)))
    (conj! lines (str "Constellation entities: " (:entity-count summary)))
    (conj! lines (str "Constellation edges: " (:edge-count summary)))

    (when (seq missing-entities)
      (conj! lines "")
      (conj! lines "## Missing (referenced by relay, not in constellation)")
      (doseq [eid missing-entities]
        (conj! lines (str "  - " eid))))

    (when (seq quiet-entities)
      (conj! lines "")
      (conj! lines "## Quiet (in constellation, no recent relay activity)")
      (doseq [eid quiet-entities]
        (conj! lines (str "  - " eid))))

    (when (seq active-entities)
      (conj! lines "")
      (conj! lines "## Active (by relay mention count)")
      (doseq [{:keys [id mentions new?]} active-entities]
        (conj! lines (str "  - " id ": " mentions
                          (when new? " [NEW]")))))

    (when (seq unmapped-tags)
      (conj! lines "")
      (conj! lines "## Unmapped tags")
      (doseq [{:keys [tag count]} unmapped-tags]
        (conj! lines (str "  - " tag " (" count " messages)"))))

    (str/join "\n" (persistent! lines))))
