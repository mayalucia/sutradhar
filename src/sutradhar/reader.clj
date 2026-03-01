(ns sutradhar.reader
  "Parse sūtra relay messages and scan repositories."
  (:require [clj-yaml.core :as yaml]
            [clojure.java.io :as io]
            [clojure.java.shell :as shell]
            [clojure.string :as str]))

;; === Relay message parsing ===================================================

(defn- split-frontmatter
  "Split a markdown file into [yaml-str body-str].
   Returns [nil full-text] if no frontmatter found."
  [text]
  (if-let [[_ yaml body] (re-matches #"(?s)---\s*\n(.*?)\n---\s*\n(.*)" text)]
    [yaml body]
    [nil text]))

(defn- extract-title
  "Extract the first H1 heading from markdown."
  [body]
  (some->> (str/split-lines body)
           (some #(when (str/starts-with? % "# ")
                    (str/trim (subs % 2))))))

(defn- extract-sections
  "Extract H2 sections as a map of lowercase-title → body-text."
  [body]
  (let [lines (str/split-lines body)]
    (loop [remaining lines
           current-key nil
           current-lines []
           sections {}]
      (if (empty? remaining)
        (if current-key
          (assoc sections current-key (str/trim (str/join "\n" current-lines)))
          sections)
        (let [line (first remaining)]
          (if (str/starts-with? line "## ")
            (recur (rest remaining)
                   (str/lower-case (str/trim (subs line 3)))
                   []
                   (if current-key
                     (assoc sections current-key
                            (str/trim (str/join "\n" current-lines)))
                     sections))
            (recur (rest remaining)
                   current-key
                   (conj current-lines line)
                   sections)))))))

(defn parse-message
  "Parse a single relay message file. Returns a map with
   :filename, :date, :from, :tags, :title, :sections, :body-length."
  [file]
  (let [text (slurp file)
        [yaml-str body] (split-frontmatter text)
        meta (when yaml-str (yaml/parse-string yaml-str))]
    {:filename (.getName file)
     :date     (get meta :date "")
     :from     (get meta :from "")
     :tags     (vec (get meta :tags []))
     :title    (extract-title body)
     :sections (extract-sections body)
     :body-length (count body)}))

(defn read-relay
  "Read all relay messages from a directory, sorted chronologically."
  [relay-dir]
  (->> (file-seq (io/file relay-dir))
       (filter #(str/ends-with? (.getName %) ".md"))
       (sort-by #(.getName %))
       (mapv parse-message)))

;; === Repository scanning =====================================================

(defn- git-log
  "Run git log in a directory, return seq of {:hash :subject :date}."
  [repo-dir & {:keys [n] :or {n 20}}]
  (let [result (shell/sh "git" "log" (str "-" n)
                         "--format=%H|%s|%aI"
                         :dir (str repo-dir))]
    (when (zero? (:exit result))
      (->> (str/split-lines (:out result))
           (remove str/blank?)
           (mapv (fn [line]
                   (let [[hash subject date] (str/split line #"\|" 3)]
                     {:hash hash :subject subject :date date})))))))

(defn- list-files
  "List files in a git repo matching a glob pattern."
  [repo-dir pattern]
  (let [result (shell/sh "git" "ls-files" pattern
                         :dir (str repo-dir))]
    (when (zero? (:exit result))
      (vec (remove str/blank? (str/split-lines (:out result)))))))

(defn scan-repo
  "Scan a git repository for basic structure.
   Returns {:path, :recent-commits, :org-files, :cljs-files}."
  [repo-dir]
  (let [dir (io/file repo-dir)]
    (when (.isDirectory dir)
      {:path (str dir)
       :recent-commits (git-log dir :n 10)
       :org-files (list-files dir "*.org")
       :cljs-files (list-files dir "*.cljs")})))

;; === Tag taxonomy ============================================================

(def tag->entities
  "Map relay tags to constellation entity IDs they reference.
   This is the knowledge the sūtradhār uses to connect relay
   activity to the visual constellation."
  {"bravli"                ["bravli"]
   "constellation"         ["thread-project-browser"]
   "writing"               ["writing"]
   "story"                 ["writing"]
   "sutra-genesis"         ["writing"]
   "autonomy"              ["thread-autonomy"]
   "protocol"              ["sutra"]
   "sutra"                 ["sutra"]
   "inference"             ["bravli" "thread-mayadevgenz"]
   "project-dahaka"        ["thread-mayadevgenz"]
   "mayadevgenz"           ["thread-mayadevgenz"]
   "agency"                ["thread-mayadevgenz"]
   "epistemic-dependencies" ["thread-mayadevgenz"]
   "website"               ["website"]
   "deployment"            ["website"]
   "diamond"               ["thread-project-browser"]
   "cartography"           ["parbati"]})

(defn entity-activity
  "Given parsed messages, compute a map of entity-id → [filenames]
   showing which entities are referenced by relay activity."
  [messages]
  (reduce
    (fn [acc msg]
      (reduce
        (fn [acc2 tag]
          (reduce
            (fn [acc3 eid]
              (update acc3 eid (fnil conj []) (:filename msg)))
            acc2
            (get tag->entities tag [])))
        acc
        (:tags msg)))
    {}
    messages))
