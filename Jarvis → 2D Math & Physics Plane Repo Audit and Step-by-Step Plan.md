````````markdown
# TASK: Extend Jarvis with `jarvis-plane` (2D math and physics plane). Exact, step-by-step specification

You are implementing this in https://github.com/OwaisShaikh1/jarvis (audited at commit `2a22ed1`, 2 commits). Common Lisp, SBCL >= 2.2.9, ASDF. Follow the steps in order. Every step has: files, exact change, and a "Done when" check. Do not skip a step. Do not invent features not listed. If the repo contradicts a statement here, stop and report it before continuing.

---

## 0. Global conventions (apply to every step)

- One git commit per step, message `step <ID>: <summary>`. Run the full test suite before each commit.
- Test framework: FiveAM. Test systems: `jarvis-tests` (`tests/jarvis-tests.asd`) and `jarvis-plane-tests` (`plane/tests/jarvis-plane-tests.asd`). Runtime systems must load WITHOUT Quicklisp; only test systems may need `fiveam`.
- Run tests with: `sbcl --noinform --non-interactive --eval '(require :asdf)' --eval '(ql:quickload :fiveam)' --load tests/run-tests.lisp`. `run-tests.lisp` must exit with status 1 if any test fails.
- Code style: match existing files (section banner comments, docstring on every function, `jarvis.<layer>` package names, symbols such as `FACT-12`).
- All user-level symbols (predicates, entity names, rule names) are interned in `CL-USER`. Keep this: the demo and persisted data already rely on it.
- Test output isolation: tests must bind `jarvis.persistence:*data-dir*` to a fresh temp directory so they never touch `data/`.
- Security: never call `eval` on user text; never read with `*read-eval*` enabled; subprocesses only through `sb-ext:run-program` with an argument list (never a shell string).
- Never claim a step is done unless its "Done when" command passes.

---

## 1. Verified facts about the repository

**Layout:** `jarvis.asd` (serial; Layers 1-5 real; Layers 6-10 are `defpackage`-only stubs of 3 lines each, meta-controller 12); `src/knowledge`, `src/inference`, `src/truth-maintenance`, `src/trace`, `src/graph`; `main.lisp` (1018 lines, package `cl-user`: demo `main`, CLI `jarvis-cli`/`jarvis-cli-handle-command`, persistence, explainers); `data/facts.txt`, `data/rules.txt`; `run.lisp`, `run-cli.lisp`, `load-system.lisp`; `.tmp-negative-test.lisp`, `.tmp-negative-contradiction-test.lisp`, `.tmp-root-cause-test.lisp` (print only, no assertions); `.tmp-output.txt` (UTF-16, PowerShell capture); `architecture.md`, `setup steps.md`, `docs/cli-commands-report.md`, `README.md`.

**Data model:**
- `fact`: `id predicate args negative-p derived-p usage-count last-accessed`. Constructor `(make-fact predicate &rest args)` assigns id `FACT-n` from a global counter that is never reset.
- `rule`: `id name conditions conclusion negative-p priority usage-count`. Conditions = list of flat patterns; conclusion = one flat pattern; negative conclusion written `(! p ...)`, `(not p ...)` or `(!p ...)`.
- Variables: symbols whose name starts with `?`. Bindings: alist.
- `justification`: `derived-id rule-id parent-ids`; exactly ONE per derived fact in `jarvis.truth-maintenance:*justification-table*`; reverse map `*dependents-table*`.
- Hooks: `jarvis.inference:*on-rule-fired*` (lambda (rule bindings new-fact)), `*on-cycle-end*`.
- Trace: `begin-trace-session` installs a recorder into `*on-rule-fired*`; `end-trace-session` sets it to NIL. Trace steps: `rule-id input-ids output-id depth`.
- Graph: own hash-table DAG; node types `:fact :rule`; edge relations `:input-of :produces`. `cl-graph`, `alexandria`, `cl-ppcre` are in `:depends-on` but never called.
- Persistence: `data/facts.txt`/`data/rules.txt` as `prin1` plists (`:predicate :args :negative :derived`), relative paths, saved after add-fact/add-rule/infer/retract/reset.
- `equal` is used on fact arguments in exactly these 7 places: (1) `store-fact` and (2) `fact-exists-p` in `knowledge.lisp`; (3) `unify` bound-variable check and (4) `unify` ground-atom check in `inference.lisp`; (5) `inputs-from-bindings` in `trace.lisp`; (6) `handle-add-fact-command` (`already`) and (7) `register-opposite-polarity-contradictions` in `main.lisp`.

**Defects reproduced in SBCL (each must get a failing test first, then a fix):**

| ID | Defect | Observed |
|---|---|---|
| P1 | numbers compared with `equal` | `mass(b1,2)` does not match pattern `(mass ?b 2.0)` |
| P2 | no arithmetic; `apply-bindings` is flat | conclusion `(speed ?b (/ ?d ?t))` stored literally as `speed(b1, (/ ?D ?T))` |
| P3 | variable bound to `NIL` is treated as unbound | `p(a,nil)` and `q(a,z)` join on `?y` and the rule fires |
| P4 | one justification per fact, unconditional cascade | `mortal(a)` has two supports; retracting `human(a)` removes `mortal(a)` |
| P5 | `run-inference` alone writes no justifications | table size 0; only the CLI wrapper fills it |
| P6 | re-running inference | existing derived facts reported as new, trace step re-recorded, justification overwritten |
| P7 | rules with a fully ground condition never fire | `unify` returns the empty bindings `NIL` on success, which `match-conditions` treats as failure; `((alive plato) (human ?x)) => (ok ?x)` and `((alive plato)) => (ok plato)` both derive 0 facts |
| P8 | unbound variable in a conclusion is accepted | rule `((human ?x)) => (likes ?x ?y)` stores `likes(a, ?Y)` |
| P9 | `variable-p` signals `INVALID-ARRAY-INDEX-ERROR` on a symbol with an empty name | |

**Other defects (from reading code):** `parse-one-form` and `load-persistent-state` use `read-from-string`/`read` with `*read-eval*` enabled (`add-fact #.(...)` executes code); persistence paths are cwd-relative and persisted derived facts reload without justifications; `agenda-push` uses unstable `sort` and `lookup-facts` without predicate iterates a hash table (non-reproducible order); `run.lisp`, `run-cli.lisp`, `load-system.lisp` hard-code `c:/Users/OWAIS/MyStuff/Projects/AAAA My projects/AI/jarvis/`; the `.tmp-*` scripts call `(load "main.lisp")` and assume the system is already loaded; CLI commands write to `data/` so golden captures mutate it.

---

## 2. Binding decisions

1. `jarvis-plane` is a separate ASDF system in `plane/` (same repository), depending on `jarvis`. `jarvis` never depends on `jarvis-plane`. Core receives only the fixes and extension points in Stage A.
2. Complete numeric control: tolerance-aware matching is allowed in the logic layer through a pluggable `term-equal`; exact matching remains the default and a selectable mode.
3. Algebra: a native engine AND an optional Maxima backend behind one CLOS protocol, selectable at runtime, with a cross-check mode.
4. Layers 6-10 will later learn from plane derivations; Stage C builds the data they need but does not implement them.
5. **Numbers are stored in fact arguments as plain Lisp numbers in SI base units.** Dimensions live in registries (`param` kinds and predicate schemas), not inside facts. Uncertainty and units live in `fact-meta`.

---

# STAGE A: core (`jarvis`)

## A0. Baseline and hygiene

**A0.1 Portable paths.** In `load-system.lisp`, `run.lisp`, `run-cli.lisp` replace the hard-coded `pushnew` with:
```lisp
(require :asdf)
(defparameter cl-user::*jarvis-root*
  (make-pathname :name nil :type nil :version nil :defaults *load-truename*))
(pushnew cl-user::*jarvis-root* asdf:*central-registry* :test #'equal)
```
and replace `(load "main.lisp")` with `(load (merge-pathnames "main.lisp" cl-user::*jarvis-root*))`. Done when: from a different working directory, `sbcl --non-interactive --load /path/to/jarvis/run.lisp` prints the demo.

**A0.2 Dependencies.** Delete `"cl-graph" "alexandria" "cl-ppcre"` from `:depends-on` in `jarvis.asd`. Update README and `setup steps.md` ("Install Lisp dependencies via Quicklisp" becomes optional, test-only). Done when: `sbcl --non-interactive --eval '(require :asdf)' --eval '(asdf:load-system "jarvis")'` succeeds on a machine without Quicklisp.

**A0.3 Golden transcripts.** Create `tests/golden/`. Capture (UTF-8) with `sbcl --noinform --non-interactive ... > file 2>&1`: `demo.txt` (run.lisp); `negative.txt`, `negative-contradiction.txt`, `root-cause.txt` from `--load load-system.lisp --load <script>`. After EACH capture run `git checkout -- data/` (the CLI saves state into `data/`). Tag `baseline-v0.1`. Golden files are only regenerated at steps that say "golden changes allowed".

**A0.4 Real tests.** Create `tests/jarvis-tests.asd`, `tests/package.lisp`, `tests/core-tests.lisp`, `tests/run-tests.lisp`. Port the `.tmp-*` scripts as assertions: (a) `negative`: after `add-fact (alive plato)`, `add-rule alive-implies-!dead ((alive ?x)) (!dead ?x)`, `infer`, a negative derived fact `dead(plato)` exists; (b) `negative-contradiction`: with `(dead plato)` also asserted, `check-contradictions` returns T; (c) `root-cause`: as in the script, `check-contradictions` returns T and its output contains `Option 1` and `Option 2`. Capture output with `with-output-to-string`. Then add one failing test per defect P1-P9 marked `(fiveam:def-test ... (:expected-failure))` style or skipped-with-reason, enabled by the step that fixes it. Delete the three `.tmp-*.lisp` files and `.tmp-output.txt`. Done when: tests run and the baseline tests pass.

**A0.5 Reader safety.** In `parse-one-form` and in `load-persistent-state` wrap every read in `(let ((*read-eval* nil) (*package* (find-package :cl-user)) (*read-default-float-format* 'double-float)) ...)`. Add a comment explaining why `cl-user` is fixed. Test: `add-fact #.(+ 1 2)` prints a parse error and the KB is unchanged. Done when: the test passes.

**A0.6 Persistence location.** Introduce `(defvar *data-dir* (asdf:system-relative-pathname :jarvis "data/"))` and functions `(facts-file)` = `(merge-pathnames "facts.txt" *data-dir*)`, `(rules-file)`. Remove `*persistence-dir*`, `*facts-file*`, `*rules-file*`. Write floats with `*read-default-float-format*` bound to `double-float` so doubles round-trip as `1.5` and singles print as `1.5f0`. Done when: running the CLI from another directory saves into the repo's `data/`.

**A0.7 Split `main.lisp`.** Create modules (add to `jarvis.asd` after `src/graph`, serial):
- `src/persistence/{package,persistence}.lisp`: package `jarvis.persistence` exporting `*data-dir* facts-file rules-file save-persistent-state load-persistent-state fact->record record->fact rule->record record->rule`.
- `src/cli/{package,parse,explain,commands,demo,repl}.lisp`: package `jarvis.cli` (uses `cl`, `jarvis.knowledge`, `jarvis.inference`, `jarvis.truth-maintenance`, `jarvis.trace`, `jarvis.graph`, `jarvis.persistence`) exporting `jarvis-cli jarvis-cli-handle-command main`. Move the demo (`section`, `print-derivation-graph`, `main`) to `demo.lisp`.
- `main.lisp` becomes three wrappers in `cl-user`: `(defun main () (jarvis.cli:main))`, `(defun jarvis-cli () (jarvis.cli:jarvis-cli))`, `(defun jarvis-cli-handle-command (line) (jarvis.cli:jarvis-cli-handle-command line))`.
Done when: all four golden transcripts are byte-identical to A0.3.

## A1. Core fixes (golden changes allowed only where stated)

**A1.1 Bindings and unification (P3, P7, P9).** In `inference.lisp`:
```lisp
(defparameter +no-bindings+ '((t . t)))   ; success marker; never NIL

(defun variable-p (x)
  (and (symbolp x)
       (let ((n (symbol-name x)))
         (and (plusp (length n)) (char= (char n 0) #\?)))))

(defun lookup-binding (var bindings)
  "Return (values value found-p)."
  (let ((cell (assoc var bindings :test #'eq)))
    (if cell (values (cdr cell) t) (values nil nil))))

(defun unify (pattern fact-args &optional (bindings +no-bindings+))
  (let ((bindings (or bindings +no-bindings+)))
    (cond ((and (null pattern) (null fact-args)) bindings)
          ((or (null pattern) (null fact-args)) nil)
          (t (let ((p (car pattern)) (f (car fact-args)))
               (cond ((variable-p p)
                      (multiple-value-bind (bound found) (lookup-binding p bindings)
                        (if found
                            (when (term-equal bound f)
                              (unify (cdr pattern) (cdr fact-args) bindings))
                            (unify (cdr pattern) (cdr fact-args) (acons p f bindings)))))
                     ((term-equal p f) (unify (cdr pattern) (cdr fact-args) bindings))
                     (t nil)))))))
```
`rebuild-agenda` calls `(match-conditions conds +no-bindings+)`. Export `+no-bindings+`. Hook callbacks now receive bindings containing the `(t . t)` cell; document it. Until A2.1 lands, `term-equal` is a local alias of `equal`. Done when: P3 and P7 tests pass.

**A1.2 Recursive `apply-bindings` (P2 part).**
```lisp
(defun apply-bindings (template bindings)
  (cond ((variable-p template)
         (multiple-value-bind (v found) (lookup-binding template bindings)
           (if found v template)))
        ((consp template) (cons (apply-bindings (car template) bindings)
                                (apply-bindings (cdr template) bindings)))
        (t template)))
```
Done when: a rule with conclusion `(f (g ?x))` derives `f((g a))`.

**A1.3 Range restriction (P8).** In `jarvis.knowledge` define `(define-condition rule-error (error) ((message :initarg :message :reader rule-error-message)))`. `make-rule` signals it when the conclusion has a variable not occurring in some positive condition pattern (A2.3 extends "bound variables" to `:is` targets). The CLI `add-rule` catches it and prints `[add-rule] <message>`. Done when: P8 test passes and the persisted-rule loader skips (with a printed warning) invalid rules instead of aborting.

**A1.4 Determinism (stable order).** (a) `agenda-push`: append at the end, then `stable-sort` by descending priority. (b) `lookup-rules` and `all-facts`: sort ties/all by numeric suffix of the id (helper `(id-number sym)` parsing the digits after the last `-`). Done when: running the demo twice (after clearing KB, TMS, traces) yields identical sequences of `(rule-name predicate args)` in the trace.

**A1.5 No re-reporting (P6).** `fire-rule` returns `(values fact newp)` where `newp` is true iff `store-fact` returned the object just created. `run-inference` pushes only `newp` facts to its result. `*on-rule-fired*` is now called as `(funcall hook rule bindings fact newp)`; update the trace recorder lambda to `(rule bindings new-fact &optional newp)`. Done when: running `infer` twice reports 0 new facts the second time (P6 test).

**A1.6 Single inference path (P5).** Create package `jarvis.engine` (`src/engine/{package,engine.lisp}`, loaded after `src/graph`, before `src/persistence`), using knowledge, inference, truth-maintenance, trace. Export `infer` and `assert-derived` (A2.7).
```lisp
(defun infer (&key goal (max-cycles 1000) rules quiet) ...)  ; -> (values new-facts trace)
```
Behaviour: open a trace session; compose a hook that, per firing, (1) if the output fact is derived (`fact-derived-p` true) computes `input-ids` with `jarvis.trace:inputs-from-bindings` (export it) and calls `add-justification` (never add a justification to a root fact), then (2) calls the trace recorder; `unwind-protect` closes the session and restores the hook; `quiet` binds `*standard-output*` to a null stream. The CLI `infer` command and `run-inference-with-trace-and-tms` become thin callers (the latter keeps contradiction registration/checking and saving). Golden changes allowed: `root-cause.txt` now shows derivation lines for derived facts. Done when: after `jarvis.engine:infer`, the justification table size equals the number of derived facts (P5 test).

**A1.7 Persistence of derived facts.** `save-persistent-state` writes only root facts (`derived` NIL) and rules. `load-persistent-state` ignores any record with `:derived t` (backward compatible with the current `data/facts.txt`), then calls `(jarvis.engine:infer :quiet t)`. Done when: add facts and rules, save, `reset` in-memory, load: derived facts reappear with justifications and `retract` cascades.

## A2. Extension points

**A2.1 `term-equal` (E1).** In `jarvis.knowledge` (exported):
```lisp
(defvar *term-equal-hook* nil
  "NIL or (lambda (a b) -> :equal | :unequal | NIL for no opinion).")
(defvar *match-context* nil
  "Bound by UNIFY to (predicate position pattern-args) when *TERM-EQUAL-HOOK* is non-NIL.")

(defun term-equal (a b)
  (cond ((and (consp a) (consp b))
         (and (term-equal (car a) (car b)) (term-equal (cdr a) (cdr b))))
        (t (case (and *term-equal-hook* (funcall *term-equal-hook* a b))
             (:equal t) (:unequal nil) (t (equal a b))))))
(defun term-identical (a b) (equal a b))          ; exact structural identity
(defun args-equal (x y)     (and (= (length x) (length y)) (every #'term-equal x y)))
(defun args-identical (x y) (equal x y))
```
`unify` takes the predicate as an extra internal argument and binds `*match-context*` per argument only when the hook is non-NIL. **Exact site table** (apply in this order):
| Site | Use |
|---|---|
| `store-fact` dedup | `args-identical` unless `(fact-meta-get fact :dedup)` is `:policy` or the dynamic variable `*dedup-uses-policy*` is true, then `args-equal` |
| `fact-exists-p` | `args-equal` |
| `unify` (two places) | `term-equal` |
| `inputs-from-bindings` | `args-equal` |
| `handle-add-fact-command` `already` | same rule as `store-fact` dedup |
| `register-opposite-polarity-contradictions` | `args-equal` |
Also grep for every other `equal`, `eql`, `member`, `assoc` applied to fact args and review each. Done when: with the hook NIL, all golden transcripts are unchanged; with a test hook returning `:equal` for any two numbers within 1d-9, `mass(b1,2.0000000001)` matches pattern `(mass ?b 2.0)`.

**A2.2 Fact metadata (E2).** Add slot `(meta nil :type list)` to `fact`; export `fact-meta`, `(setf fact-meta)`, `(fact-meta-get fact key)`; add constructor `(make-fact* predicate args &key meta negative-p derived-p)` (keep `make-fact` unchanged). Persistence: `fact->record` adds `:meta` only when non-NIL; `record->fact` restores it. Standard meta keys (all optional): `:status` (`:given :tuned :derived :inferred :observed`), `:unit` (string), `:method`, `:tolerance`, `:error`, `:sigma`, `:interval` `(lo hi)`, `:expr`, `:law`, `:episode`, `:signature`, `:prunable` (boolean), `:dedup`. Show meta in `facts`, `why`, graph labels (`fact-label` appends ` [status unit]` only when present). Done when: a fact with meta survives save/load and appears in `facts`.

**A2.3 Procedural attachment (E3).** Extended condition grammar (rules only; facts unchanged):
```
condition ::= pattern | (:test expr) | (:is ?var expr)
pattern   ::= (predicate term*)            ; predicate must be a non-keyword symbol
expr      ::= number | ?var | (op expr*)   ; op is a symbol compared by SYMBOL-NAME, case-insensitive
```
Rules: `:test`/`:is` may reference only variables bound by EARLIER conditions (patterns or earlier `:is`); `make-rule` signals `rule-error` otherwise, also for any other keyword predicate. Semantics in `match-conditions`: patterns as before; `(:test e)` continues iff `(evaluate e bindings)` returns non-NIL; `(:is ?v e)` evaluates; if `?v` is bound compares with `term-equal`, else binds it. An evaluator error makes that condition fail and pushes a `diagnostic` struct `(kind rule-name message bindings)` onto `jarvis.inference:*diagnostics*` (cleared by `clear-diagnostics`). The evaluator is `jarvis.inference:*expression-evaluator*`, a function `(lambda (expr bindings) value)` signalling `eval-error`. Core default evaluator supports `+ - * / expt sqrt abs min max floor ceiling = /= < > <= >= and or not` on real numbers only. `inputs-from-bindings` must skip `:test`/`:is` conditions. A1.3's "bound variables" now include `:is` targets. CLI `valid-pattern-p`/`add-rule` must accept the new forms. Done when: `add-rule speed ((dist ?b ?d) (time ?b ?t) (:test (> ?t 0)) (:is ?s (/ ?d ?t))) (speed ?b ?s)` with `dist(b1,10)`, `time(b1,2)` derives `speed(b1,5)`; with `time=0` derives nothing and records one diagnostic.

**A2.4 Multi-justification TMS (E4, fixes P4).** `*justification-table*` maps fact-id to a LIST of justifications (distinct by `(rule-id, set of parent-ids)`; duplicates ignored). New exports: `justifications-for` (all); `justification-for` returns the first (compat). `*dependents-table*`: parent-id to list of derived ids (set semantics). New `retract-with-support (fact-id)`:
1. If the fact is not in the KB, return NIL.
2. `removed = {fact-id}`. `affected` = transitive dependents of `fact-id` that are still in the KB. `out = copy(affected)`.
3. A parent `p` is IN iff `p` is in the KB and `p` is not in `removed` and not in `out`.
4. Repeat until no change: for each `id` in `out`, if some justification of `id` has all parents IN, remove `id` from `out`. (Well-founded: mutual support among affected facts does not keep them alive.)
5. `removed = removed ∪ out`. For each removed id: `retract-fact`, delete its justifications, unlink it from every `dependents` entry. For each surviving affected fact, drop justifications that mention a removed id.
6. Return `removed` sorted by id number.
The retracted target is always removed even if it was derived with other supports (a later `infer` can re-derive it). `supported-p`: derived fact is supported iff some justification has all parents in the KB. Update `dependency-parents` (union over justifications), `trace-roots-recursively` and `collect-root-facts` (union of roots over all justifications; follow the first justification whose parents are all in the KB; `visited` set prevents cycles), `format-derivation-proof`, and in the CLI `explain-why-immediate` (print all justifications, numbered), `explain-why-recursive` and `explain-proof-forward` (follow the first fully supported justification and print `(+n alternative support(s))`). Done when: the P4 test keeps `mortal(a)` after retracting `human(a)`; a cyclic-support test (A derives B, B derives A, only A has an external root) removes both when the root goes.

**A2.4b Contradictions.** `check-contradictions` uses the new root collection and prints Option 1 / Option 2 as before (no auto retraction).

**A2.5 Assumptions (E5).** In `jarvis.engine`:
```lisp
(defun replace-assumption (fact-id new-args &key meta)
  "FACT-ID must be a root (non-derived) fact. If NEW-ARGS is ARGS-IDENTICAL to the old args, return (values old NIL).
   Else retract-with-support the old fact, store a new root fact with the same predicate/polarity,
   META = (or META old-meta), return (values new-fact retracted-ids). Does not run inference."
```
Done when: a unit test shows cascade removal of dependents and a new root fact id.

**A2.6 Restricted inference (E6).** `run-inference` and `rebuild-agenda` accept `:rules` (list of rule structs). `(affected-rules changed-predicates)`: start `S = changed-predicates`; repeat: add the conclusion predicate of every rule that has a pattern condition with predicate in `S`; stop at fixpoint; return the rules touched. `jarvis.engine:infer-incremental (changed-predicates)` = `(infer :rules (affected-rules ...))`. Done when: with 1000 unrelated facts/rules, changing one parameter leaves `rule-usage-count` of rules outside the affected set unchanged.

**A2.7 Derivation records and events (E7).** In `jarvis.inference`:
```lisp
(defstruct derivation-record
  id output episode-id newp
  kind        ; :rule :symbolic :numeric :inferred :tuned :assumed
  method      ; symbol: RULE:<name>, SYM:NATIVE.SOLVE, SYM:MAXIMA.DIFF, NUM:RK45, NUM:NEWTON, INF:LM, TUNE:SET ...
  inputs      ; alist (role-symbol . fact-id), roles COND-1.. for rules
  signature   ; canonical sexp (C.2) or NIL
  meta)       ; plist: :policy :error :backend :is-exprs :expr :residual ...
(defvar *on-derivation* nil)   ; (lambda (record))
```
`fire-rule` (via `run-inference`) emits a record of kind `:rule` (`method` = `RULE:<rule-name>`, `signature` filled by `*signature-function*` if set). `jarvis.engine:assert-derived`:
```lisp
(defun assert-derived (predicate args &key kind method inputs meta negative-p)
  "Store a derived fact (derived-p T, fact-meta META), add a justification with rule-id = METHOD and
   parent-ids = fact ids in INPUTS, emit a derivation-record, return (values fact newp).")
```
This is the ONLY sanctioned way for `jarvis-plane` to create derived facts. Trace subscribes to `*on-derivation*`: `reasoning-trace` gets a `derivations` list; `trace-step` gets slots `kind method meta newp`. `jarvis.trace` also gets episodes: `(begin-episode goal)`/`(end-episode outcome)` (struct `episode`: `id goal outcome start end derivation-ids`), `*current-episode*`, `*episode-store*`, `clear-traces` clears it. `rule-label` in `jarvis.graph` falls back to the symbol name when the id is not in `*rule-db*`. Done when: calling `assert-derived` with `:method 'num:rk45` creates a fact whose `why` shows `[from NUM:RK45]`.

**A2.8 Scratch KB.** `jarvis.engine:with-scratch-kb (&body)` copies facts (fresh `fact` structs) and rules, rebinds `*fact-db*`, `*rule-db*`, `*principle-db*`, both predicate indexes, `*justification-table*`, `*dependents-table*`, `*contradiction-pairs*`, `*trace-store*`, `*active-session*`, `*on-derivation*`, and discards all changes on exit. Needed by inference (B9) and sweeps. Done when: a test mutates inside the macro and the outer KB is unchanged.

---

# STAGE B: `jarvis-plane`

## B1. System layout
Create `plane/jarvis-plane.asd`:
```lisp
(asdf:defsystem "jarvis-plane"
  :depends-on ("jarvis")
  :serial t
  :pathname "src/"
  :components ((:file "package") (:file "numeric") (:file "units") (:file "expr")
               (:file "model") (:file "algebra-protocol") (:file "algebra-native")
               (:file "algebra-maxima") (:file "algebra-crosscheck")
               (:file "numerics") (:file "sim") (:file "laws") (:file "infer")
               (:file "explain") (:file "svg") (:file "cli")))
```
Test system `plane/tests/jarvis-plane-tests.asd` depends on `jarvis-plane` and `fiveam`. Law data: `plane/data/laws/{geometry,kinematics,dynamics}.laws`. `package.lisp` defines one package per area: `jarvis.plane.numeric`, `.units`, `.expr`, `.model`, `.algebra`, `.numerics`, `.sim`, `.laws`, `.infer`, `.explain`, `.cli`. Loading `jarvis-plane` installs: `jarvis.knowledge:*term-equal-hook*`, `jarvis.inference:*expression-evaluator*`, `jarvis.inference:*signature-function*`, and registers its CLI commands through `jarvis.cli:register-command` (add this to A0.7's CLI: a hash table name -> function `(lambda (tokens line))`, consulted by `jarvis-cli-handle-command` before the unknown-command branch, plus help text registration).

## B2. Numeric policy (`numeric.lisp`)
```lisp
(defstruct numeric-policy
  (domain :double)        ; :rational :single :double
  (match :exact)          ; :exact :absolute :relative :combined :ulps
  (abs-eps 1d-12) (rel-eps 1d-9) (ulps 4)
  (dedup :exact)          ; :exact | :policy  (store-fact duplicate rule)
  (traps '(:invalid :overflow :divide-by-zero))  ; fp conditions that become diagnostics
  (display-digits nil)    ; significant figures for DISPLAY only; NIL = full
  (seed 12345))
```
Scopes and resolution order for matching (first hit wins): `(:pred predicate position)` > `(:param-kind name)` (only for predicate `param`, position 2, name taken from the literal in pattern position 1) > `(:pred predicate)` > `:global`. API: `(set-policy scope policy)`, `(effective-policy predicate position pattern-args)`, `*policies*`.
Number equality `(numbers-match-p a b policy)`: `:exact` = `(= a b)` (cross-type: `2` and `2.0` are equal; `0.1d0` and `1/10` are not); `:absolute` `|a-b| <= abs-eps`; `:relative` `|a-b| <= rel-eps*max(|a|,|b|)` (both zero = equal); `:combined` `|a-b| <= max(abs-eps, rel-eps*max(|a|,|b|))`; `:ulps` convert both to double, compare ordered-integer representations of the bit patterns, `|ia-ib| <= ulps`, +0 and -0 equal, NaN never equal. The installed `*term-equal-hook*` returns `:equal`/`:unequal` only when both args are real numbers (using `*match-context*`), else NIL. Domain rules: `:double` coerces rationals to `double-float` at first arithmetic use; `:rational` keeps exact rationals and signals `inexact-in-rational-domain` for `sin cos tan exp log` and for `sqrt`/`expt` with a non-exact result; `:single` coerces to `single-float`. Float traps: wrap evaluation in `sb-int:with-float-traps-masked (:overflow :invalid :divide-by-zero :inexact)` and check results: NaN or infinity whose kind is in `traps` signals `numeric-diagnostic` (becomes an `eval-error`); exact rational division by zero always signals. Determinism: any random draw uses `(seeded-rng seed)` (a portable LCG: `x' = (1103515245 x + 12345) mod 2^31`, uniform = `x'/2^31`; normal via Box-Muller). Commands (B8): `numeric-policy [show]`, `numeric-policy set <scope> <key> <value> ...` (scope written `global`, `pred:<p>`, `pred:<p>:<pos>`, `param:<name>`). Persist policies in `data/policy.txt`. Done when: tests for all five match modes (including the case `2.0000000001` vs `2.0`: exact no, relative 1e-9 yes, ulps 4 no) and domain rules pass; two identical runs produce byte-identical `(format nil "~S" (all-facts-as-records))`.

## B3. Units, quantities, evaluator (`units.lisp`, `expr.lisp`)

**Dimensions:** vector of five integers `(L M T I Theta)` (length, mass, time, current, temperature); angle is dimensionless, internal unit radian. `(dim* a b)`, `(dim/ a b)`, `(dim-expt a n)`, `(dim= a b)`.
**Unit table (exhaustive for this task):** `m km cm mm kg g s ms min h N J W Pa Hz rad deg K A` plus `m/s`-style compounds. Factors to SI: `km 1000`, `cm 1/100`, `mm 1/1000`, `g 1/1000`, `ms 1/1000`, `min 60`, `h 3600`, `deg pi/180`, `N = kg m s^-2`, `J = N m`, `W = J/s`, `Pa = N/m^2`, `Hz = s^-1`.
**Grammar:** `quantity ::= number ws+ unit`; `unit ::= factor (("*"|"/") factor)*`; `factor ::= name ("^" integer)?`. API: `(parse-quantity "9.81 m/s^2")` -> `(values si-value dimension)`; `(format-quantity value dimension &optional unit)`. `struct quantity (value dimension)` is used only inside the evaluator and parser, never stored in facts.
**Registries (`model.lisp`):** `(def-param-kind name &key dimension (bounds '(nil nil)) default-unit)`; built-ins: `mass (M)`, `x y length v0 vx vy (L, L, L, L T^-1...)`, `angle ()`, `g (L T^-2)`, `k (M T^-2)`, `mu ()`, `drag (M T^-1)`, `time (T)`, etc. (list the full set you need for the tests). `(declare-predicate-dims predicate dim-list)` gives the dimension of each numeric argument position (`:entity`/`:sym` for non-numeric).
**Evaluator (`expr.lisp`):** `(evaluate expr bindings &key policy)`; whitelist (by symbol-name, case-insensitive): `+ - * / expt sqrt sin cos tan atan2 exp log abs min max = /= < > <= >= and or not distinct`; numbers, bound `?vars`, and nothing else; any other symbol signals `eval-error "operator not allowed"`. `(distinct a b)` is true iff `a` and `b` are not `eq`. Comparison `=` uses `numbers-match-p` with the effective global policy. `atan2` takes `(y x)`. Installed into `jarvis.inference:*expression-evaluator*`.
**Dimension check:** `(expr-dimension expr var-dims)`: number -> dimensionless; variable -> from `var-dims`; `+ - min max` and comparisons -> all args must be `dim=` else signal `dimension-mismatch`; `*`/`/` combine; `(expt x n)` requires literal rational `n`, result `dim-expt`; `sqrt` halves; `sin cos tan exp log` require dimensionless arguments, return dimensionless; `atan2` requires equal dims, returns dimensionless; `abs` keeps. `(check-rule-dimensions rule)` infers variable dimensions from pattern positions using `param` kinds and predicate dims, walks every `:is`/`:test`, and compares each `:is` result with the dimension declared for the position of the same variable in the conclusion. `*dimension-check*` is `:strict` (default; mismatch rejects the rule), `:warn`, or `:off`; variables of unknown dimension produce a warning in `:warn`/`:strict`. Hook it into `add-rule` for plane rules. Done when: tests cover `m/s * s = m`, reject `m + s`, `sqrt(m^2) = m`, `30 deg` = 0.5235987755982988d0 rad, unit parse errors.

## B4. Plane model (`model.lisp`)
- **Frames:** `(defstruct frame name parent ox oy rotation scale)`; `world` is the root (ox=oy=rotation=0, scale=1). `(frame->world frame x y)` returns world point: `p = origin + scale * R(rotation) * (x,y)`, applied up the parent chain; `(world->frame frame x y)` inverts it. Check: frame at (1,2) rotated 90 degrees, local (1,0) -> world (1,3).
- **Primitives as facts:** `(point name frame x y)`, `(vector name frame x y)`, `(line name frame a b c)` (ax+by+c=0), `(segment name p1 p2)`, `(circle name frame cx cy r)`, `(polygon name p1 p2 ...)`, `(curve name frame x-expr y-expr t0 t1)` (expressions as quoted s-expressions in `meta :expr`).
- **Entities:** `(entity name type)` with types `particle rigid-body spring incline wall field-region`. Parameters: `(param entity name value)` with meta `:status` (`:given :tuned :inferred :derived`), `:unit`, `:bounds`, `:sigma`. Global parameters use entity `world` (e.g. `(param world g 9.81)`). Assumptions: `(assumption scope name)` root facts with `:status :given`. `add-entity` registers the entity in `*entity-registry*` (name -> type) and asserts the facts. Bounds are enforced by `set`.
- **Schema:** `(def-entity-type type &key params)` lists the parameters each type may carry (name, kind, required-p). `add-entity` rejects unknown parameters.
- Done when: tests for frame round-trips, entity creation, bounds rejection pass.

## B5. Algebra (`algebra-*.lisp`)
**AST:** s-expressions; numbers (rationals exact), symbols as variables, `(+ ...)`, `(* ...)`, `(expt b e)`, `(sin x) (cos x) (tan x) (exp x) (log x) (sqrt x)`. `(to-canonical e)` rewrites `(- a b)` -> `(+ a (* -1 b))`, `(- a)` -> `(* -1 a)`, `(/ a b)` -> `(* a (expt b -1))`, `(sqrt x)` stays.
**Protocol (generic functions on a `backend` object):** `alg-simplify (backend expr)`, `alg-substitute (backend expr alist)`, `alg-diff (backend expr var)`, `alg-solve (backend equation var)` (equation `(= lhs rhs)`; returns a list of solution expressions, each tagged `(:exact e)` or `(:numeric value)`), `alg-evaluate (backend expr bindings policy)`, `alg-capabilities (backend)` -> plist e.g. `(:diff t :solve (:linear :quadratic :numeric))`. Backends: `native-backend`, `maxima-backend`, `crosscheck-backend` (holds two). `*algebra-backend*` global; command `algebra-backend native|maxima|crosscheck`.
**Native:** total order for canonical form: numbers < symbols (by name) < compounds (by operator name, then arguments). `+`: flatten, fold rational constants, collect like terms `c*m` (m a monomial), drop zeros, single term unwrap. `*`: flatten, fold constants, combine equal bases into `expt`, `0` annihilates, `1` removed. `expt`: `(expt x 1)=x`, `(expt x 0)=1`, `(expt (expt x a) b)=(expt x (* a b))` only when `b` is an integer, numeric constants folded when exact. `alg-diff`: standard rules including chain rule for `sin cos tan exp log sqrt expt` (exponent a constant, or base e). `alg-solve`: form `lhs-rhs`, expand to a polynomial in `var` with coefficients free of `var`; degree 1 -> `(:exact -b/a)`; degree 2 -> two roots with the discriminant kept symbolic (`(sqrt disc)`); otherwise, if every other symbol has a numeric binding in the active KB parameters, bracket by scanning 200 points over `[lo, hi]` from the parameter bounds (or `[-1e6, 1e6]`) and refine by bisection to the policy tolerance -> `(:numeric value)`; else signal `cannot-solve`. Done when: derivative table (`x^n`, `sin`, `cos`, `exp`, `log`, product, chain), simplify round trips, `solve v^2 = u^2 + 2 a s` for each of `v u a s` pass.
**Maxima backend:** available iff `(sb-ext:find-executable-in-search-path "maxima")`. Run `sb-ext:run-program "maxima" (list "--very-quiet" "--batch-string" input) :search t :output stream :error nil :wait nil` with a wall-clock timeout `*maxima-timeout*` (default 10 s, then `process-kill`) and an output cap of 65536 bytes. `input` always starts with `display2d:false$` and ends with a single `string(<expr>);` form. Serialization from the AST uses a whitelisted printer only: variable names must match `^[a-z][a-z0-9_]*$` (else reject); numbers: integers, rationals `p/q`, doubles as `<mantissa>e<exp>`; functions map `sin cos tan exp log sqrt`; `(expt a b)` -> `a^b`. Commands: simplify -> `ratsimp(E)`; diff -> `diff(E,v)`; solve -> `solve(E=0,v)`. Output parser: tokenizer for numbers, identifiers (`%pi` -> `pi` constant 3.141592653589793d0, `%e` -> `e`), `+ - * / ^ ( ) , [ ] =`; returns an AST (a `[a=..,b=..]` list becomes a list of solutions). Not installed or any failure -> signal `backend-unavailable`; the system works fully without Maxima. Tests that need Maxima are skipped with a reason when it is absent.
**Selection and fallback:** per-call override `(with-backend (b) ...)`; if the selected backend lacks the capability or signals `backend-unavailable`/`cannot-solve`, fall back to native and record `:backend :native :fallback-from <b>` in the derivation meta.
**Cross-check:** run both backends; compare results by evaluating both at 8 deterministic sample points per free variable (seeded RNG from the policy seed, values in `[0.5, 3.5]`, skipping points where either evaluation signals), using the effective policy; disagreement signals a warning and records `:crosscheck :disagree` plus both expressions in meta, never a silent pick. Result method symbols: `SYM:NATIVE.<OP>`, `SYM:MAXIMA.<OP>`, `SYM:CROSSCHECK.<OP>`.
**Recording:** every symbolic result is asserted with `assert-derived` (kind `:symbolic`), args `(<symbol> <expr-as-list>)` is NOT used; instead store results as facts `(symbolic-result <entity-or-name> <quantity-name> <expr>)` with `meta :expr`, `:backend`, inputs = the fact ids of the premises used.

## B6. Numerics (`numerics.lisp`)
All use `double-float`. States are simple-vectors.
- `(rk4 f t0 y0 t1 h)` -> `(values y-final steps)`; classic RK4; the last step is shortened to land exactly on `t1`.
- `(rk45 f t0 y0 t1 &key (rtol 1d-9) (atol 1d-12) (h0 nil) (hmax nil) (max-steps 100000) events)` Dormand-Prince 5(4) with FSAL. Error norm: `sqrt(mean_i (e_i / (atol + rtol * max(|y_i|, |ynew_i|)))^2)`. Accept when norm <= 1. `h_new = h * min(5, max(0.2, 0.9 * norm^(-1/5)))`. Initial `h0` default `0.01 * (t1-t0)`. Exceeding `max-steps` signals `step-limit`. Returns `(values t-list y-list status stats)` with `stats` = `(:steps :rejected :max-error-estimate)`.
- **Events:** `(event name fn direction terminal)` where `fn: (t y) -> real`, `direction` `:rising :falling :both`. After each accepted step, detect a sign change of `fn`; refine on cubic Hermite interpolation using bisection until the t-interval is below `event-tol` (default 1d-12); record `(name t y)`; stop if `terminal`.
- `(newton-solve F x0 &key jac (ftol 1d-12) (xtol 1d-12) (max-iter 50))`: `F` returns a vector; finite-difference central Jacobian with `h_i = cbrt(double-float-epsilon) * max(1, |x_i|)` when `jac` is NIL; linear solve by Gaussian elimination with partial pivoting (singular -> status `:singular`); backtracking damping: halve the step up to 8 times until the residual 2-norm decreases; converged when `||F||_inf <= ftol` or `||dx|| <= xtol * (1 + ||x||)`. Returns `(values x status iterations residual)` with status in `:converged :max-iter :singular`.
- `(levenberg-marquardt residual-fn p0 &key bounds (lambda0 1d-3) (max-iter 100) (ftol 1d-12) (xtol 1d-12))`: Jacobian by central differences; step solves `(JtJ + lambda*diag(JtJ)) dp = -Jt r`; accept and divide lambda by 10 if SSR decreases else multiply by 10; parameters are clamped into `bounds`. Returns a plist: `:p :ssr :iterations :status :jacobian`. **Covariance:** `sigma2 = SSR / (m - n)` (m residuals, n parameters; if `m = n` use 1), `cov = sigma2 * inverse(JtJ)`. **Identifiability:** eigen-decompose the symmetric `JtJ` with cyclic Jacobi rotations (tolerance 1d-14, max 100 sweeps); if `min-eig / max-eig < 1d-10` report `:non-identifiable` with the eigenvector of the smallest eigenvalue (the unidentifiable combination, e.g. proportional to `(k m)` for the spring).
- All routines take the active `numeric-policy` for tolerances only when the caller passes none; results include method, tolerance used and error estimate for recording by `assert-derived` (B6.1).
**B6.1** Result facts: `(numeric-result <entity> <name> <value>)` with `assert-derived` (kind `:numeric`, method `NUM:RK45`/`NUM:NEWTON`/`NUM:RK4`), meta `:method :rtol :atol :steps :error :policy-seed`, inputs = the parameter fact ids used.
Done when: RK4 on `y'=-y` (y(0)=1, t=1) within 1e-6 of e^-1 with h=0.01; RK45 within `rtol`; Newton solves `x^2-2=0` to 1e-12; LM recovers `a=2, b=3` from noiseless `a*x+b` data; Jacobi eigen test on a known 3x3.

## B7. Simulation (`sim.lisp`) and laws (`laws.lisp`)
**Simulation models (registry `register-sim-model name builder`)**, each builds the ODE and events from entity parameters:
- `:ballistic` for a `particle`: state `(x y vx vy)`; acceleration `(-c vx / m, -g - c vy / m)` with `g` from `(param world g ...)` and `c` from `(param <particle> drag ...)` (default 0); event `y = 0` falling, terminal; initial `y0`, `x0` default 0; initial velocity `(v0 cos angle, v0 sin angle)`.
- `:spring-1d`: state `(x v)`, `x'' = -(k/m) x` with params `k mass x0 v0` (rest position 0).
- `:incline-slide`: state `(s v)`, `s'' = g (sin(angle) - mu cos(angle))` with params `angle mu`, stops (terminal event) when `s = distance` param.
Command `simulate <entity> <model> <t-end> [dt]` runs `rk45` (policy tolerances), stores the full sample in `*trajectories*` (id `TRAJ-n`, not as facts), and asserts summary facts `(sim-result <entity> <model> <key> <value>)` for keys `flight-time apex-height apex-time range final-x final-y final-s final-t` (those that apply) with `assert-derived` (method `NUM:RK45`, meta `:trajectory TRAJ-n`).
**Law file format** (read with `*read-eval*` NIL; one form per law):
```lisp
(:law projectile-range
 :doc "Range of a drag-free projectile on flat ground."
 :assumes ((assumption world no-drag) (assumption world flat-ground))
 :conditions ((param ?b v0 ?v) (param ?b angle ?a) (param world g ?g)
              (assumption world no-drag)
              (:is ?r (/ (* (expt ?v 2) (sin (* 2 ?a))) ?g)))
 :conclusion (range ?b ?r)
 :dimensions ((range :entity (L))))
```
`enable-law name` asserts the `:assumes` root facts (`:status :given`) and stores the rule (named after the law) after `check-rule-dimensions`; `disable-law` retracts the assumption facts (cascading) and removes the rule. A registry maps law name -> doc, assumptions, rule id, dimensions; `laws` lists them. Ship these laws (one test each, with the numeric check shown in section 6): **geometry:** `distance` (two points same frame: `(:is ?d (sqrt (+ (expt (- ?x2 ?x1) 2) (expt (- ?y2 ?y1) 2))))` with `(:test (distinct ?p ?q))`), `slope`, `polygon-area` (shoelace, 3- and 4-vertex forms), `circle-tangent-line` (tangent at point `P` on circle `(cx,cy,r)`: `a = px-cx`, `b = py-cy`, `c = -(a*px + b*py)`; condition `(:test (= (+ (expt (- px cx) 2) (expt (- py cy) 2)) (expt r 2)))`), `line-circle-intersects` (distance from center to line vs r); **kinematics:** `v-final` (`v = u + a t`), `displacement` (`s = u t + a t^2/2`), `v2` (`v^2 = u^2 + 2 a s`), `projectile-range`, `projectile-apex` (`(* (expt v 2) (expt (sin a) 2)) / (* 2 g)`), `projectile-time` (`2 v sin(a) / g`), `circular-period` (`2 pi r / v`); **dynamics:** `newton-2` (`a = F / m` per axis), `incline-acceleration` (`g (sin(angle) - mu cos(angle))`), `hooke-force` (`-k x`), `spring-period` (`2 pi sqrt(m/k)`), `kinetic-energy`, `torque-alpha` (`alpha = tau / I`). Use the constant `pi` as the number `3.141592653589793d0` substituted at load time. Done when: each law fires on the test data and `enable-law`/`disable-law` cascades correctly.

## B8. Commands (all registered through `register-command`; keep every existing command working; fact ids accepted as `FACT-1 fact1 fact#1 1`)

| Command | Syntax | Behaviour and output |
|---|---|---|
| `plane-new` | `plane-new` | clears plane state (entities, observations, trajectories, scratch policies), keeps core KB; prints `[plane] new plane` |
| `add-entity` | `add-entity <name> <type> [<param>=<number>[<unit>] ...]` | e.g. `add-entity b1 particle mass=2.5kg v0=20m/s angle=45deg`; asserts facts with `:status :given`, prints `[add-entity] b1 particle: 3 parameter(s)` |
| `set` | `set <entity>.<param> <number> [unit]` | uses `replace-assumption`, then `infer-incremental`; status becomes `:tuned`; prints `[set] b1.v0: 20 -> 25 m/s`, `[set] retracted N: <ids>`, `[set] re-derived M`, and one line `changed: <pred>(<non-numeric args>) <old> -> <new> <unit>` for each derived numeric fact whose `fact-key` (predicate + non-numeric args) matched before and after; rejects values outside `:bounds` without changing anything |
| `unset` | `unset <entity>.<param>` | retracts with cascade, prints the removed ids |
| `numeric-policy` | see B2 | |
| `show-model` | `show-model` | entities, parameters (value, unit, status, bounds), enabled laws, assumptions |
| `laws`, `enable-law`, `disable-law` | `enable-law <name>` | |
| `derive` | `derive <predicate> [<arg> ...]` | if a matching fact exists, print it with its `why`; else backward analysis: for rules whose conclusion predicate matches, check conditions recursively (depth limit 8) against facts; if every leaf is present, run `infer` and print the result; else print `[derive] missing premises:` followed by the missing leaf patterns |
| `simulate` | `simulate <entity> <model> <t-end> [dt]` | see B7 |
| `sweep` | `sweep <e>.<p> <from> <to> <n> [<e2>.<p2> <from2> <to2> <n2>] -> <predicate> [<entity>]` | n >= 2, inclusive linspace; runs inside `with-scratch-kb`; prints a table (parameter values, output); the real KB is untouched; `export <file.csv>` writes the last sweep |
| `sensitivity` | `sensitivity <predicate> [<entity>] wrt <e>.<p>` | symbolic derivative if the derivation expression is available (`meta :expr` chain), else central difference with step `1e-6*max(1,|p|)`; prints value and units (output unit / parameter unit) |
| `observe` | `observe <entity> <quantity> <number> [unit] [sigma=<number>]` | asserts `(observation OBS-n <entity> <quantity> <value>)`, `:status :observed`, `:sigma` (default 0 meaning exact) |
| `infer-params` | `infer-params <entity> <p1>[,<p2>...] [bounds <p>=<lo>,<hi> ...]` | see B9 |
| `uncertainty` | `uncertainty <fact-id> [monte-carlo <n>]` | re-evaluates the fact's `:is` expressions (stored in the derivation meta `:is-exprs`, inputs from the derivation record) with inputs drawn from `N(value, sigma)` using the seeded RNG; prints mean, sd, min, max; default n = 1000 |
| `algebra-backend` | `algebra-backend native\|maxima\|crosscheck` | |
| `explain` | `explain <fact-id-or-predicate>` | `why -r` output plus, per line: unit, status, method, tolerance, error estimate |
| `model-card` | `model-card` | sections in order: Entities, Parameters (value, unit, status, bounds), Enabled laws, Assumptions, Observations, Inferred parameters (value ± sigma), Unresolved unknowns (parameters required by enabled laws with no value), Numeric policy |
| `export` | `export <json\|csv> <file>` | trajectories, last sweep, parameter table |
| `plot` | `plot <trajectory-id> <file.svg>` | B10 |
| `plane-reset` | `plane-reset` | `plane-new` plus `reset` |

Errors print `[<command>] <message>` and never leave the KB half-modified. Update `help` and `docs/cli-commands-report.md`.

## B9. Inference (`infer.lisp`)
**Prediction function:** `(predict entity quantity params-alist)`: inside `with-scratch-kb`, replace each listed parameter with `replace-assumption`, run `infer-incremental` (and `simulate` if the quantity is a `sim-result` key), then read the first numeric fact for `quantity`. A quantity name denotes either a derived predicate (`range`, `distance`, ...) or a `sim-result` key.
**Algorithm of `infer-params entity p1,p2,...`:**
1. Collect observations for the entity (those with matching quantity names). Require number of observations >= number of unknowns, else error.
2. **Algebraic attempt** (only if one unknown): build the symbolic expression of each observed quantity in terms of the unknown by substituting the stored `:is-exprs` chain (recorded in derivation meta) with the current parameter values for every other parameter; solve `(= observed expr)` with `alg-solve`. If the result is `(:exact e)` and evaluates within bounds, use it (method `INF:ALGEBRAIC`, no covariance, sigma from first-order propagation of the observation sigma using `alg-diff`).
3. Otherwise **LM** (`levenberg-marquardt`) on residuals `(predict(obs) - observed) / sigma_i` (sigma 0 is replaced by `max(1e-12, 1e-9*|observed|)`), starting at the current parameter values (or the midpoint of the bounds when unset), within bounds.
4. Report: estimates, standard errors `sqrt(diag cov)`, residual norm, iterations, status, and **identifiability** warnings from B6 (`non-identifiable` with the unidentifiable direction, printed as `only the combination <p1/p2> is determined`). If status is `:non-identifiable` the estimate is still stored but flagged.
5. Store each estimate with `assert-derived`... no: store as a ROOT `(param <entity> <p> <value>)` with `:status :inferred`, `:sigma`, `:covariance`, `:residual-norm`, `:method`, `:obs-ids`, and emit a derivation record of kind `:inferred` (method `INF:LM` or `INF:ALGEBRAIC`, inputs = observation ids). If a root `param` fact already exists, replace it through `replace-assumption`.
6. **Consistency / nogoods:** let `chi2 = SSR` (weighted). If `chi2 / max(1, m - n) > 9` (more than 3 sigma per datum on average) or an algebraic solution is outside bounds, declare inconsistency and compute minimal conflicting sets by deletion-based minimization: candidates = observation facts + root parameters with `:status :given` or `:tuned` + enabled-law assumption facts (cap 12 candidates, else report "too many candidates"); a subset is inconsistent if refitting without the other candidates still fails the chi2 test; start with all, try removing each candidate and keep the removal if the set stays inconsistent; print every minimal set found as `[nogood] {FACT-a, FACT-b, ...}`, then print the root-cause explanation using the existing `check-contradictions` format. Never force a fit.
Done when: the acceptance tests in section 6 (incline, spring, contradiction) pass.

## B10. Explanation, visualization, export (`explain.lisp`, `svg.lisp`)
- `explain` and `why` display `[unit]` using the unit table (smallest listed unit that gives a value in `[1, 1000)`, else SI), status, method, tolerance, error estimate, `:backend`, and for inferred facts `value ± sigma (n obs, residual r)`.
- **SVG:** `(write-svg trajectory-id path)`: 800x500 viewBox; axes with 5 ticks each (round numbers), polyline for the trajectory (x vs y), small circles at event points (apex, impact) with text labels `apex (x, y)`; velocity vector arrows every N samples (N = max(1, samples/10)); title with entity and model; deterministic output (same input -> identical file bytes). No external dependencies. ASCII fallback `plot-ascii` (60x20 grid) printed to the terminal when the file is `-`.
- **Export:** JSON written by a small internal writer (strings escaped, numbers printed with `*read-default-float-format*` double-float, no trailing commas); CSV with a header row and `,` separator, `\n` line endings.
Done when: SVG test checks element counts and that two runs are byte-identical; JSON round-trips through a minimal parser in the tests.

---

# STAGE C: learning-ready design for Layers 6-10

Do not implement Layers 6-10. Implement exactly the following so they can learn from plane derivations later.

**C.1 Derivation record.** The struct in A2.7 is the single record format for rule, symbolic, numeric, inferred, tuned and assumed derivations. `TUNE:SET` records (kind `:tuned`) are emitted by `set`; `INF:*` by `infer-params`.

**C.2 Derivation signature (algorithm).** Installed into `jarvis.inference:*signature-function*` by `jarvis-plane`. For a record, build `(:method M :inputs (A1 ... An) :output B)` where inputs are sorted by role name (`string<`) and each fact is abstracted by `abs`:
```
abs(fact)  = (predicate [!] a1' ... an')     ; "!" present iff negative
a'         = number                    -> (:num DIM)  ; DIM from predicate dims / param kind, else :unknown
             symbol registered entity  -> (:ent k TYPE) ; k = index of first occurrence of that entity
                                            scanning inputs in order, then the output (0-based)
             any other symbol           -> itself      ; keeps parameter and law names such as MASS
             list                       -> element-wise
```
Two derivations have equal signatures iff same method and same shape, regardless of concrete numbers and entity names.

**C.3 Trace and graph extensions.** Pseudo-rule ids (`NUM:*`, `SYM:*`, `INF:*`, `TUNE:*`) allowed in trace steps; steps carry `kind method meta newp`; each session records its `episode-id`. Graph: new node types `:quantity` (numeric fact nodes whose label shows `value unit`), `:numeric-step`, `:assumption` (facts with `:status :given/:tuned`); new edge relation `:solved-from`; `node-signature` ignores concrete numbers but includes node type and dimension; `isomorphic-p` uses the updated signature. `fact-label`/`rule-label` as in A2.2/A2.7. Done when: the same derivation with different numeric inputs gives isomorphic graphs.

**C.4 Template extraction (test-only proof of concept).** In `plane/tests`, `(extract-template records-a records-b)`: align records pairwise by equal `signature`; for each aligned pair produce the signature with every `(:num DIM)` slot replaced by `(:var n DIM)` (n numbered in order of appearance) and a parameter table listing the two concrete values. Returns NIL if any pair mismatches. Done when: two projectile episodes with different `v0` and `angle` yield one template with `:var` slots and non-empty parameter tables.

**C.5 Prunable markers.** Facts with `:status` `:given :tuned :inferred :observed` get `:prunable nil`; numeric cache facts (`sim-result`, `numeric-result`, `symbolic-result`) get `:prunable t`. `usage-count` and `last-accessed` are touched by plane reads through `touch-fact`.

**C.6 Controller hooks.** `jarvis.trace:begin-episode`/`end-episode` wrap every `set`, `sweep`, `simulate` and `infer-params`; the `episode` struct stores `goal`, `outcome` (`:ok :failed :inconsistent`), `start`/`end` (internal real time), `derivation-ids`, and a summary plist `(:steps n :depth d :residual r :backend b :seconds s)` for future scoring. Expose `(episode-summary id)`.

---

# 6. Acceptance tests (each is an automated test with these exact numbers; tolerances shown)

1. **Projectile (no drag):** `g=9.81`; `b1`: `v0=20 m/s`, `angle=45 deg`. Laws enabled: `projectile-range`, `-apex`, `-time`. Expect `range = 40.77472 m` (1e-4), `apex = 10.19368 m` (1e-4), `flight-time = 2.88321 s` (1e-4). RK45 `:ballistic` with `drag=0` matches these within 1e-6 relative; with `drag=0.1`, `mass=1` the simulated range is strictly less than the closed-form range.
2. **Incline:** `angle=30 deg`, `g=9.81`, `mu=0.2`, `distance=5 m`: law gives `a = 3.20586 m/s^2` (1e-5); simulated slide time = `1.76614 s` (1e-4). Observe `slide-time = 1.76614 s`; with `mu` unknown, `infer-params b2 mu` returns `0.2` (1e-5) by the algebraic path (method `INF:ALGEBRAIC`).
3. **Spring:** `k=50`, `mass=2`: law `spring-period` gives `1.256637 s` (1e-6). Generate `x(t)=0.1 cos(5 t)` at 50 equally spaced times over `[0, 2.5133]` with seeded (seed 12345) Gaussian noise sigma `1e-3`; observe them with `sigma=1e-3`. With `mass` known (=2), `infer-params s1 k` returns `k` within 3 standard errors of 50. With both `k` and `mass` unknown, status is `:non-identifiable` and the report says only `k/mass` is determined (the smallest-eigenvalue eigenvector has equal-sign components with ratio close to `(k : mass) = (50 : 2)` normalized).
4. **Geometry:** circle `(0,0,5)` and point `(3,4)` on it: `circle-tangent-line` derives line `(3, 4, -25)`; a point `(4,4)` (not on the circle) derives nothing and produces no diagnostic. `distance` between `(0,0)` and `(3,4)` = `5`. Polygon area of `(0,0),(4,0),(4,3),(0,3)` = `12`.
5. **Contradiction:** incline `b2` with `mu=0.2` given, observation 1 `slide-time=1.76614 s` (sigma 1e-4) and observation 2 `slide-time=2.5 s` (sigma 1e-4), asking `infer-params b2 mu`: status inconsistent; the printed nogoods include `{given mu, obs-2}` and `{obs-1, obs-2}`.
6. **Numeric control:** fact `mass(b1, 2.0000000001)`, rule pattern literal `2.0`: policy `:exact` no match; `:relative` with `rel-eps 1d-9` match; `:ulps 4` no match. A rational-domain evaluation of `(sqrt 2)` signals `inexact-in-rational-domain`. Two identical runs give byte-identical fact records and trace step lists.
7. **Backends:** native and Maxima agree on `diff(sin(x)*x^2, x)`, `solve(x^2-5x+6=0, x)` = `{2,3}`, and `solve(v^2 = u^2 + 2 a s, a)` (skipped cleanly when Maxima is absent); a deliberately corrupted backend (test double returning `x` for any diff) makes crosscheck signal a disagreement warning.
8. **TMS:** P4 case keeps `mortal(a)`; cyclic support case removes both facts when the external root is retracted.
9. **Learning-ready:** two projectile episodes (different numbers, different entity names) produce identical `signature` lists and `extract-template` returns one template with `:var` slots.
10. **Regression:** all A0.3 golden transcripts match except the changes explicitly allowed in A1.6; all P1-P9 tests pass; `set` on a 1000-fact KB re-fires no rule outside the affected set.

---

# 7. Delivery protocol

1. **First reply:** (a) reproduce P1-P9 and print the outputs, (b) list any discrepancy between section 1 and the code, (c) restate the plan as a checklist of step IDs. Ask at most 3 questions, only about things the repository and this document cannot answer.
2. Implement in this order, stopping for review after each group: A0; A1; A2.1-A2.3; A2.4-A2.8; B1-B3; B4; B5 (native); B6; B7; B8-B9; B5 (Maxima, cross-check); B10; Stage C; final docs (`README.md`, `architecture.md`, `docs/cli-commands-report.md`, `plane/README.md`).
3. After each group show: files changed, how to run it, the test results, and a short CLI transcript.
4. No stubs presented as features. If something is deferred, say so explicitly and add a failing-marked test for it.
5. If anything here is ambiguous or contradicted by the code, stop, say what, and propose a concrete resolution rather than choosing silently.
````````